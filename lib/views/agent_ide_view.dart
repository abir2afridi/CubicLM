import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/cubicweb/cubicweb_logger.dart';
import '../services/runtime/cli_manager.dart';
import '../services/runtime/project_detector.dart';
import 'system_logs_view.dart';
import 'cubicweb/agent_preview.dart';
import 'cubicweb/chat_cards.dart';
import 'cubicweb/file_cards.dart';
import 'cubicweb/project_sheets.dart';
import 'cubicweb/version_timeline.dart';
import '../widgets/cli_sheets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/agent_workspace.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import '../widgets/app_ui.dart';
import '../widgets/model_switcher_sheet.dart';

/// CubicWeb Builder — agentic website studio (Toolkit): prompt → project
/// → live localhost preview → console-error auto-fix loop.
class AgentIdeView extends StatefulWidget {
  const AgentIdeView({super.key});

  @override
  State<AgentIdeView> createState() => _AgentIdeViewState();
}

class _AgentIdeViewState extends State<AgentIdeView> {
  late final AgentController c;
  final _promptCtrl = TextEditingController();
  final _askCtrl = TextEditingController();
  final _askFocus = FocusNode();
  final _termCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  final _expandedFolders = <String>{}.obs;
  String _tab = 'preview'; // preview | files | terminal
  String? _openFile;

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<AgentController>()
        ? Get.find<AgentController>()
        : Get.put(AgentController());

    _askCtrl.addListener(() {
      if (mounted) setState(() {});
    });

    ever(c.generating, (_) {
      if (mounted) setState(() {});
    });
    ever(c.fixing, (_) {
      if (mounted) setState(() {});
    });
    ever(c.project, (_) {
      if (mounted) setState(() {});
    });

    ever(c.transcript, (_) {
      if (!mounted) return;
      _scrollToBottom();
    });
    ever(c.buildSteps, (_) {
      if (!mounted) return;
      _scrollToBottom();
    });

    ever(c.streamingFiles, (_) {
      if (!mounted) return;
      if (_openFile == null && c.streamingFiles.isNotEmpty && _tab == 'files') {
        setState(() => _openFile = c.streamingFiles.keys.first);
      }
    });

    _termCtrl.addListener(() {
      if (mounted) setState(() {});
    });

    ever(c.requestAskFocus, (_) {
      if (mounted) _askFocus.requestFocus();
    });

    unawaited(c.ensureTerminalWelcome());

    ever(c.detectedCliId, (_) {
      if (!mounted) return;
      final id = c.detectedCliId.value;
      if (id == null || id.isEmpty) return;
      c.detectedCliId.value = null;
      try {
        final m = Get.find<CliManagerService>().manifestById(id);
        if (m == null) return;
        showCliDetectedDialog(m, c.detectedCliVersion.value ?? '');
      } catch (_) {}
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _askCtrl.dispose();
    _askFocus.dispose();
    _termCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final isMod = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isMod && event.logicalKey == LogicalKeyboardKey.enter) {
          _sendFromAskBar();
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit1) {
          setState(() => _tab = 'preview');
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit2) {
          setState(() => _tab = 'files');
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit3) {
          setState(() => _tab = 'chat');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final p = c.project.value;
            if (p == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('CubicWeb Builder',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800)),
                  Text('Agent IDE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).hintColor)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800)),
                Text('${p.framework} · ${c.files.length} files',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor)),
              ],
            );
          }),
          actions: [
            Obx(() {
              final hasP = c.project.value != null;
              final dim = Theme.of(context).hintColor.withValues(alpha: 0.45);
              return Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: hasP ? 'History' : 'History (needs a project)',
                  icon: Icon(LucideIcons.history,
                      size: 20, color: hasP ? Dt.accent : dim),
                  onPressed: hasP ? () => showHistorySheet(context) : null,
                ),
                IconButton(
                  tooltip: hasP
                      ? 'Auto-fix ${c.autoFix.value ? 'on' : 'off'}'
                      : 'Auto-fix (needs a project)',
                  icon: Icon(
                      c.autoFix.value
                          ? Icons.bolt_rounded
                          : Icons.bolt_outlined,
                      size: 20,
                      color: !hasP
                          ? dim
                          : (c.autoFix.value
                              ? Dt.accent
                              : Theme.of(context).hintColor)),
                  onPressed:
                      hasP ? () => c.autoFix.value = !c.autoFix.value : null,
                ),
                IconButton(
                  tooltip: hasP
                      ? (c.elementPickMode.value
                          ? 'Pick mode on — click an element in preview'
                          : 'Pick an element in preview to edit')
                      : 'Pick element (needs a project)',
                  icon: Icon(LucideIcons.crosshair,
                      size: 20,
                      color: !hasP
                          ? dim
                          : (c.elementPickMode.value
                              ? Dt.accent
                              : Theme.of(context).hintColor)),
                  onPressed: hasP ? () => c.toggleElementPick() : null,
                ),
              ]);
            }),
            IconButton(
              tooltip: 'New project',
              icon: const Icon(LucideIcons.plus, size: 20, color: Dt.accent),
              onPressed: _newProjectReset,
            ),
            Obx(() {
              int n = 0;
              try {
                n = Get.find<CubicWebLogger>().unreadErrors.value;
              } catch (_) {}
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'CubicWeb System Logs',
                    icon: Icon(LucideIcons.activity,
                        size: 20,
                        color: n > 0
                            ? AppColors.error
                            : (isDark
                                ? AppColors.textPrimary
                                : Dt.iconDefault)),
                    onPressed: () => Get.to(() => const SystemLogsView(),
                        transition: Transition.rightToLeft,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic),
                  ),
                  if (n > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            n > 99 ? '99+' : '$n',
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
            }),
            Obx(() {
              final hasP = c.project.value != null;
              return PopupMenuButton<String>(
                tooltip: 'Project',
                icon: Icon(LucideIcons.folderGit2,
                    color: hasP
                        ? (isDark ? AppColors.textPrimary : Dt.iconDefault)
                        : Theme.of(context).hintColor.withValues(alpha: 0.45)),
                onSelected: (v) =>
                    onProjectMenu(context, v, promptCtrl: _promptCtrl),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'switch',
                    child: Text('Switch project (${c.projectsOf().length})',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                  ),
                  const PopupMenuItem(
                    value: 'new',
                    child: Text('New project', style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    enabled: hasP,
                    child: const Text('Export ZIP',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    enabled: hasP,
                    child: const Text('Rename project',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'fork',
                    enabled: hasP,
                    child: const Text('Fork project',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'deploy',
                    enabled: hasP,
                    child: const Text('Deploy to web',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    enabled: hasP,
                    child: const Text('Share project link',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'github',
                    enabled: hasP,
                    child: const Text('Export to GitHub',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: hasP,
                    child: Text('Delete project',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: AppColors.error)),
                  ),
                ],
              );
            }),
            const SizedBox(width: 4),
          ],
        ),
        body: Obx(() {
          final hasProject = c.project.value != null;
          final wide = MediaQuery.of(context).size.width >= 900 && hasProject;
          if (wide) {
            return Row(children: [
              VersionTimeline(isDark: isDark),
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        flex: 2,
                        child: Column(children: [
                          _paneHeader(context, isDark, 'CHAT', null),
                          Expanded(child: _chatPane(context, isDark)),
                        ]),
                      ),
                      Container(
                        width: 1,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Dt.hairline,
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(children: [
                          _paneHeader(
                              context,
                              isDark,
                              _tab == 'files' ? 'FILES' : 'LIVE PREVIEW',
                              SegmentedButton<String>(
                                showSelectedIcon: false,
                                style: SegmentedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: Colors.transparent,
                                  selectedBackgroundColor: Dt.accent.withValues(alpha: 0.1),
                                  selectedForegroundColor: Dt.accent,
                                  side: BorderSide.none,
                                ),
                                segments: const [
                                  ButtonSegment(
                                      value: 'preview',
                                      label: Text('Preview', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      icon: Icon(LucideIcons.eye, size: 14)),
                                  ButtonSegment(
                                      value: 'files',
                                      label: Text('Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      icon: Icon(LucideIcons.fileCode, size: 14)),
                                ],
                                selected: {_tab == 'files' ? 'files' : 'preview'},
                                onSelectionChanged: (s) =>
                                    setState(() => _tab = s.first),
                              )),
                          Expanded(
                            child: _tab == 'files'
                                ? _filesPane(context, isDark)
                                : _previewPane(context, isDark, c.revision.value),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  if (c.lastError.value != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(_friendlyError(c.lastError.value!),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5, color: AppColors.error, height: 1.4)),
                    ),
                  _askBar(context, isDark),
                ]),
              ),
            ]);
          }
          return Column(children: [
            _tabSwitch(),
            Expanded(
              child: _tab == 'preview' && hasProject
                  ? _splitOrPreview(context, isDark)
                  : _tab == 'preview'
                      ? _previewPane(context, isDark, c.revision.value)
                      : _tab == 'files'
                          ? _filesPane(context, isDark)
                          : _chatPane(context, isDark),
            ),
            if (c.lastError.value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(_friendlyError(c.lastError.value!),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5, color: AppColors.error, height: 1.4)),
              ),
            _askBar(context, isDark),
          ]);
        }),
      ),
    );
  }

  void _sendFromAskBar() {
    if (c.generating.value || c.fixing.value) {
      c.cancelWork();
      return;
    }
    if (_askCtrl.text.trim().isEmpty && c.attachedImage.value == null) return;
    final text = _askCtrl.text.trim();
    final hasImg = c.attachedImage.value != null;
    c.topic.value =
        text.isEmpty && hasImg ? 'Build from this screenshot' : text;
    _askCtrl.clear();
    final hasProject = c.project.value != null;
    if (hasProject) {
      c.modifyProject();
    } else {
      c.newProject();
    }
  }

  void _newProjectReset() {
    c.project.value = null;
    c.files.clear();
    c.previewUrl.value = null;
    c.transcript.clear();
    c.buildSteps.clear();
    _promptCtrl.clear();
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('too many requests')) {
      return 'Rate limited — wait a moment and try again.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Request timed out — check your connection and try again.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return 'Network error — check your internet connection.';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return 'API key issue — check your provider settings.';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503')) {
      return 'Server error — the AI provider is temporarily unavailable.';
    }
    if (lower.contains('no local model loaded')) {
      return 'No model loaded — load one in Explore → Local, or switch to Cloud mode.';
    }
    if (lower.contains('model returned nothing')) {
      return 'The AI returned an empty response — try rephrasing your request.';
    }
    if (lower.contains('quota') || lower.contains('insufficient')) {
      return 'Out of credits — check your API provider balance.';
    }
    return raw;
  }

  String _pickedLabel(String info) {
    try {
      final m = jsonDecode(info) as Map<String, dynamic>;
      var tag = (m['tag'] ?? '').toString();
      var text = (m['text'] ?? '').toString().replaceAll('\n', ' ').trim();
      if (text.length > 24) text = '${text.substring(0, 24)}…';
      if (tag.isEmpty && text.isEmpty) return 'Element picked';
      if (tag.isEmpty) return text;
      if (text.isEmpty) return '<$tag> picked';
      return '<$tag> · $text';
    } catch (_) {
      return 'Element picked';
    }
  }

  Widget _paneHeader(
      BuildContext context, bool isDark, String label, Widget? trailing) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
          ),
        ),
      ),
      child: Row(children: [
        if (label == 'LIVE PREVIEW')
          Obx(() => Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      c.livePreviewReady.value ? AppColors.success : Dt.accent,
                ),
              )),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: Theme.of(context).hintColor)),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ]),
    );
  }

  Widget _tabSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'preview',
              icon: Icon(LucideIcons.eye, size: 15),
              label: Text('Preview'),
            ),
            ButtonSegment(
              value: 'files',
              icon: Icon(LucideIcons.folderOpen, size: 15),
              label: Text('Files'),
            ),
            ButtonSegment(
              value: 'chat',
              icon: Icon(LucideIcons.messageCircle, size: 15),
              label: Text('Chat'),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  Widget _askBar(BuildContext context, bool isDark) {
    final hasProject = c.project.value != null;
    final busy = c.generating.value || c.fixing.value;
    final hasContent =
        _askCtrl.text.trim().isNotEmpty || c.attachedImage.value != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.consoleError.value != null && c.consoleError.value!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(c.consoleError.value!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5, color: AppColors.error)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: c.fixing.value ? null : () => c.repairFromError(),
                  child: Text(c.fixing.value ? 'Fixing…' : 'Fix'),
                ),
              ]),
            ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                    child: TextField(
                      controller: _askCtrl,
                      focusNode: _askFocus,
                      minLines: 1,
                      maxLines: 6,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          height: 1.35,
                          color:
                              isDark ? AppColors.textPrimary : Dt.textPrimary,
                          fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: hasProject
                            ? 'Ask AI to change anything…'
                            : 'Describe what to build…',
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
                  Obx(() => c.attachedImage.value != null
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Dt.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(LucideIcons.image,
                                size: 13, color: Dt.accent),
                            const SizedBox(width: 6),
                            Text('Screenshot attached',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Dt.accent)),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => c.clearAttachment(),
                              child: const Icon(LucideIcons.x,
                                  size: 12, color: Dt.accent),
                            ),
                          ]),
                        )
                      : const SizedBox.shrink()),
                  Obx(() => c.pickedElement.value != null
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Dt.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(LucideIcons.crosshair,
                                size: 13, color: Dt.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _pickedLabel(c.pickedElement.value!),
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Dt.accent),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => c.clearPickedElement(),
                              child: const Icon(LucideIcons.x,
                                  size: 12, color: Dt.accent),
                            ),
                          ]),
                        )
                      : const SizedBox.shrink()),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    AppCircleButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Builder tools',
                      onTap: () => showBuilderToolsSheet(
                          context, isDark, hasProject,
                          askCtrl: _askCtrl,
                          onInserted: () => _askFocus.requestFocus()),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 125,
                      child: Obx(() => AppModelPill(
                            label: builderModelLabel(),
                            onTap: () => showModelSwitcherSheet(context),
                          )),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!hasProject)
                            GestureDetector(
                              onTap: () => showFrameworkSheet(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Dt.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Dt.accent.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  frameworkShort(c.framework.value),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Dt.accent),
                                ),
                              ),
                            ),
                          if (!hasProject && c.planMode.value)
                            const SizedBox(width: 6),
                          if (!hasProject && c.planMode.value)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.map,
                                        size: 12, color: Color(0xFFF59E0B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Plan',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFF59E0B)),
                                    ),
                                  ]),
                            ),
                          if (!hasProject) const SizedBox(width: 6),
                          AppCircleButton(
                            icon: LucideIcons.brain,
                            tooltip: 'Extended thinking',
                            iconColor: c.extendedThinking.value
                                ? const Color(0xFF8B5CF6)
                                : null,
                            onTap: () => c.extendedThinking.value =
                                !c.extendedThinking.value,
                          ),
                          const SizedBox(width: 6),
                          AppCircleButton(
                            icon: LucideIcons.globe,
                            tooltip: 'Web search',
                            iconColor: c.webSearch.value
                                ? const Color(0xFF10B981)
                                : null,
                            onTap: () => c.webSearch.value = !c.webSearch.value,
                          ),
                          const SizedBox(width: 6),
                          Opacity(
                            opacity: hasProject ? 1.0 : 0.35,
                            child: AppCircleButton(
                              icon: LucideIcons.shieldCheck,
                              tooltip: hasProject
                                  ? 'Auto-test project'
                                  : 'Auto-test (needs a project)',
                              onTap: (!hasProject || busy)
                                  ? null
                                  : () => c.runAutoTest(),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    Tooltip(
                      message: busy
                          ? 'Stop'
                          : (hasProject ? 'Apply change' : 'Build project'),
                      child: AppCtaButton(
                        icon: busy ? LucideIcons.square : LucideIcons.arrowUp,
                        onTap: busy
                            ? c.cancelWork
                            : (hasContent ? _sendFromAskBar : null),
                      ),
                    ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _liveProgressPill(BuildContext context, bool isDark, String? status) {
    return Obx(() {
      final n = c.streamingFiles.length;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                status ??
                    (n > 0
                        ? 'Writing $n file${n == 1 ? '' : 's'}… preview updating live'
                        : 'AI is writing…'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Dt.accent)),
          ),
        ]),
      );
    });
  }

  Widget _previewDiagnosisCard(BuildContext context, bool isDark) {
    return Obx(() {
      final steps = c.previewSteps.toList();
      final kind = c.previewKind.value;
      final blockers = c.previewIssues.where((i) => i.blocksPreview).toList();
      if (kind == ProjectKind.staticSite || steps.isEmpty) {
        return const SizedBox.shrink();
      }
      final decision = c.previewDecision.value;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: blockers.isNotEmpty
                  ? AppColors.error.withValues(alpha: 0.35)
                  : Dt.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(
                    blockers.isNotEmpty
                        ? LucideIcons.alertTriangle
                        : LucideIcons.info,
                    size: 14,
                    color: blockers.isNotEmpty ? AppColors.error : Dt.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${projectKindLabel(kind)} detected',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                if (c.devServerStarting.value)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              for (final s in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Text(
                        s.state == 'ok'
                            ? '✓'
                            : s.state == 'fail'
                                ? '✗'
                                : '…',
                        style: GoogleFonts.firaCode(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: s.state == 'ok'
                                ? const Color(0xFF4ADE80)
                                : s.state == 'fail'
                                    ? AppColors.error
                                    : Theme.of(context).hintColor)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          s.detail.isEmpty
                              ? s.label
                              : '${s.label} — ${s.detail}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: Theme.of(context).hintColor)),
                    ),
                  ]),
                ),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final b in blockers.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• ${b.message}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: AppColors.error,
                            height: 1.35)),
                  ),
              ],
              if (decision != null && decision.actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in decision.actions)
                    _diagnosisAction(context, a),
                  ActionChip(
                    label: Text('System Logs',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5, fontWeight: FontWeight.w700)),
                    avatar: const Icon(LucideIcons.activity, size: 14),
                    onPressed: () => Get.to(() => const SystemLogsView(),
                        transition: Transition.rightToLeft,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
              ],
            ]),
      );
    });
  }

  Widget _diagnosisAction(BuildContext context, String action) {
    String label;
    IconData icon;
    VoidCallback? onTap;
    switch (action) {
      case 'start-dev-server':
        label = c.devServerUrl.value != null
            ? 'Restart dev server'
            : 'Start dev server';
        icon = LucideIcons.play;
        onTap = c.devServerStarting.value
            ? null
            : () => c.devServerUrl.value != null
                ? c.restartDevServer()
                : c.startDevServer();
      case 'validate-build':
        label = 'Validate build';
        icon = LucideIcons.wrench;
        onTap = c.validatingBuild.value ? null : () => c.validateBuild();
      case 'recheck-runtime':
        label = 'Recheck runtime';
        icon = LucideIcons.rotateCw;
        onTap = () => c.recheckRuntimeAndServe();
      case 'use-cloud':
        label = 'Run in cloud';
        icon = LucideIcons.cloud;
        onTap = () => c.useCloudFallback();
      case 'export-zip':
        label = 'Export ZIP';
        icon = LucideIcons.packageOpen;
        onTap = () => c.exportZip();
      case 'fix-issues':
        label = 'Ask AI to Fix';
        icon = LucideIcons.wand2;
        onTap = () => c.fixPreviewIssues();
      case 'open-terminal':
        label = 'Terminal';
        icon = LucideIcons.terminal;
        onTap = () => setState(() => _tab = 'preview');
      default:
        return const SizedBox.shrink();
    }
    return ActionChip(
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5, fontWeight: FontWeight.w700)),
      avatar: Icon(icon, size: 14),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _previewPane(BuildContext context, bool isDark, int revision) {
    final status = c.buildStatus.value;
    final working = c.generating.value || c.fixing.value || status != null;
    final live = c.streamingActive.value && c.livePreviewReady.value;

    if (working && !live) {
      return _buildStatusView(context, isDark, status);
    }
    final url = c.previewUrl.value;
    if (url == null || url.isEmpty) {
      return Center(
        child: Text('Preview unavailable.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Theme.of(context).hintColor)),
      );
    }
    return Expanded(
      child: Column(children: [
        _previewDiagnosisCard(context, isDark),
        if (working) _liveProgressPill(context, isDark, status),
        Expanded(
          child: AgentPreview(
            url: url,
            pickMode: c.elementPickMode.value,
            onConsoleError: (e) => c.onConsoleError(e),
            onElementPicked: (info) => c.onElementPicked(info),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusView(BuildContext context, bool isDark, String? status) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Obx(() => c.attachedImage.value != null
            ? Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(LucideIcons.image, size: 13, color: Dt.accent),
                  const SizedBox(width: 6),
                  Text('Screenshot attached',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: Dt.accent)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => c.clearAttachment(),
                    child:
                        const Icon(LucideIcons.x, size: 12, color: Dt.accent),
                  ),
                ]),
              )
            : const SizedBox.shrink()),
        Row(children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(status ?? 'Working…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Obx(() => ListView.builder(
                itemCount: c.terminal.length > 12 ? 12 : c.terminal.length,
                itemBuilder: (_, i) {
                  final lines = c.terminal.toList();
                  final line =
                      lines[lines.length - (i < lines.length ? i + 1 : 1)];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 11, height: 1.5, color: _termColor(line)),
                    ),
                  );
                },
              )),
        ),
        Text('Output appears here when the structure is complete.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: const Color(0xFF8E8B85))),
      ]),
    );
  }

  Widget _chatPane(BuildContext context, bool isDark) {
    return Obx(() {
      final planPending = c.pendingPlan.value != null;
      final hasDiffs = c.lastDiffs.isNotEmpty;
      final itemCount = c.transcript.length + 
          (planPending ? 1 : 0) + 
          (hasDiffs ? 1 : 0);

      if (itemCount == 0) {
        final hasProject = c.project.value != null;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: hasProject
                ? Text(
                    'No conversation yet.\nDescribe the project above or ask for changes below — every exchange lands here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).hintColor),
                  )
                : _templateGrid(context, isDark),
          ),
        );
      }
      return ListView.builder(
        controller: _chatScroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          var idx = i;
          if (hasDiffs && idx == c.transcript.length + (planPending ? 1 : 0)) {
            return diffCard(context, isDark);
          }
          if (planPending && idx == c.transcript.length) {
            return planCard(context, isDark);
          }
          final m = c.transcript[idx];
          final role = m['role'];
          if (role == 'activity') {
            final steps = m['steps'] as List<Map<String, String>>?;
            return activityCard(context, isDark, steps: steps);
          }
          final user = role == 'user';
          return Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85),
              decoration: BoxDecoration(
                color: user
                    ? Dt.accent
                    : (isDark ? AppColors.surface : const Color(0xFFFFFFFF)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(user ? 16 : 4),
                  bottomRight: Radius.circular(user ? 4 : 16),
                ),
                border: !user && !isDark 
                    ? Border.all(color: Dt.hairline) 
                    : null,
                boxShadow: !user ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ] : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: m['text'] ?? '',
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          height: 1.5,
                          color: user
                              ? Colors.white
                              : (isDark ? AppColors.textPrimary : Dt.textPrimary)),
                      code: GoogleFonts.firaCode(
                          fontSize: 12,
                          backgroundColor: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05)),
                      codeblockDecoration: BoxDecoration(
                        color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                    ),
                  ),
                  if (!user && m['has_build'] == true) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          context,
                          isDark,
                          LucideIcons.eye,
                          'Preview',
                          () => setState(() => _tab = 'preview'),
                        ),
                        const SizedBox(width: 8),
                        _actionButton(
                          context,
                          isDark,
                          LucideIcons.fileCode,
                          'Code',
                          () => setState(() => _tab = 'files'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _actionButton(BuildContext context, bool isDark, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Dt.hairline,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Dt.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _splitOrPreview(BuildContext context, bool isDark) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!isLandscape) {
      return _previewPane(context, isDark, c.revision.value);
    }
    return Row(children: [
      Expanded(
        flex: 3,
        child: _previewPane(context, isDark, c.revision.value),
      ),
      Container(
        width: 1,
        color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
      ),
      Expanded(
        flex: 2,
        child: _filesPane(context, isDark),
      ),
    ]);
  }

  Widget _templateGrid(BuildContext context, bool isDark) {
    final templates = [
      const WebTemplate(
          'Landing Page',
          LucideIcons.rocket,
          'Marketing page with hero, features, CTA, footer',
          'Build a modern landing page with: hero section with gradient background and CTA button, features grid (3 cards with icons), testimonial section, email signup form, and footer with links. Use a professional color scheme (indigo/blue). Responsive layout.',
          'Single HTML'),
      const WebTemplate(
          'Dashboard',
          LucideIcons.layoutDashboard,
          'Admin panel with sidebar, charts, stats',
          'Build an admin dashboard with: left sidebar navigation (5 items with icons), top bar with search and user avatar, 4 stat cards (revenue, users, orders, growth), a line chart placeholder, a data table with 5 rows, and a dark sidebar with light content area. Use Tailwind-style colors.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'Portfolio',
          LucideIcons.user,
          'Personal portfolio with projects and contact',
          'Build a personal portfolio site with: animated hero with name and title, about section with photo placeholder and bio, projects grid (4 project cards with images and tech tags), skills section with progress bars, contact form, and smooth scroll navigation. Dark theme with accent color.',
          'Single HTML'),
      const WebTemplate(
          'Blog',
          LucideIcons.fileText,
          'Blog with posts, sidebar, and categories',
          'Build a blog homepage with: header with site name and nav, featured post hero, 3 article cards with image/title/excerpt/date, sidebar with categories and recent posts, newsletter signup, and footer. Clean typography, warm color palette.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'E-commerce',
          LucideIcons.shoppingCart,
          'Product grid with cart and filters',
          'Build a product listing page with: top nav with logo, search bar, and cart icon with badge, filter sidebar (category, price range), product grid (6 product cards with image, name, price, rating stars, add-to-cart button), and a mini cart dropdown. Modern clean design.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'SaaS Page',
          LucideIcons.globe,
          'Product page with pricing tiers',
          'Build a SaaS product page with: sticky nav, hero with product mockup, 3-step how-it-works section, pricing table (3 tiers: Free/Pro/Enterprise with feature comparison), customer logos bar, FAQ accordion, and CTA footer. Gradient accents, professional look.',
          'Single HTML'),
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Start from a template',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.6,
            ),
            itemCount: templates.length,
            itemBuilder: (_, i) {
              final t = templates[i];
              return GestureDetector(
                onTap: () {
                  _askCtrl.text = t.prompt;
                  _askFocus.requestFocus();
                  AppSnackbar.showTop(
                    'Template inserted',
                    'Framework: ${c.framework.value} — change it from the composer if needed.',
                    logHistory: false,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Dt.hairline),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(t.icon, size: 16, color: Dt.accent),
                        const SizedBox(height: 6),
                        Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(t.desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: Theme.of(context).hintColor)),
                      ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _termColor(String line) {
    if (line.contains('✗')) return const Color(0xFFF48771);
    if (line.contains('✓')) return const Color(0xFFA6E3A1);
    if (line.contains('⚙')) return const Color(0xFFCBA6F7);
    if (line.contains('■')) return const Color(0xFFFAB387);
    if (line.startsWith('[') && line.contains('> ')) {
      return const Color(0xFF89DCEB);
    }
    return const Color(0xFFCDD6F4);
  }

  Widget _filesPane(BuildContext context, bool isDark) {
    if (c.project.value == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Build a project above — its files will land here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.5, color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return Obx(() {
      final paths = _allFilePaths();
      final root = _buildFileTree(paths);
      final extra =
          c.streamingFiles.keys.where((k) => !c.files.contains(k)).length;
      final total = c.files.length + extra;

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  extra > 0 ? '$total files ($extra writing…)' : '$total files',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).hintColor)),
            ),
            TextButton.icon(
              onPressed: () => showAddDialog(context, isDark,
                  onPickFile: (p) => setState(() => _openFile = p)),
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('Add'),
            ),
          ]),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search in code…',
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onSubmitted: (q) => showSearchResults(context, isDark, q,
                onPickFile: (p) => setState(() => _openFile = p)),
          ),
          const SizedBox(height: 12),
          ..._renderTree(context, isDark, root.children, 0),
          if (_openFile != null &&
              (c.files.contains(_openFile) ||
                  c.streamingFiles.containsKey(_openFile))) ...[
            const SizedBox(height: 16),
            _fileEditor(context, isDark, _openFile!),
          ],
        ],
      );
    });
  }

  FileNode _buildFileTree(List<String> paths) {
    final root = FileNode(name: '', path: '', isDir: true, children: []);
    for (final path in paths) {
      final parts = path.split('/');
      FileNode current = root;
      String currentPath = '';
      for (int i = 0; i < parts.length; i++) {
        final name = parts[i];
        currentPath = currentPath.isEmpty ? name : '$currentPath/$name';
        final isLast = i == parts.length - 1;
        var existing = current.children.firstWhereOrNull((n) => n.name == name);
        if (existing == null) {
          existing = FileNode(
            name: name,
            path: currentPath,
            isDir: !isLast,
            children: [],
          );
          current.children.add(existing);
          current.children.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        }
        current = existing;
      }
    }
    return root;
  }

  List<Widget> _renderTree(
      BuildContext context, bool isDark, List<FileNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      final isExpanded = _expandedFolders.contains(node.path);
      final isWriting = c.streamingFiles.containsKey(node.path);

      items.add(
        InkWell(
          onTap: () {
            if (node.isDir) {
              if (isExpanded) {
                _expandedFolders.remove(node.path);
              } else {
                _expandedFolders.add(node.path);
              }
            } else {
              setState(() => _openFile = node.path);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: depth > 0
                            ? Theme.of(context).dividerColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        width: 1)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    node.isDir
                        ? (isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight)
                        : _iconFor(node.path),
                    size: node.isDir ? 14 : 16,
                    color: node.isDir ? Theme.of(context).hintColor : Dt.accent,
                  ),
                  const SizedBox(width: 8),
                  if (node.isDir)
                    const Icon(LucideIcons.folder, size: 16, color: Color(0xFFF59E0B)),
                  if (node.isDir) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: node.isDir ? FontWeight.w600 : FontWeight.w400,
                        color: node.path == _openFile ? Dt.accent : (isDark ? AppColors.textPrimary : Dt.textPrimary),
                      ),
                    ),
                  ),
                  if (isWriting)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Dt.accent,
                      ),
                    ),
                  if (!node.isDir)
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.moreVertical, size: 14),
                      onSelected: (v) async {
                        if (v == 'delete') {
                          final ok = await Get.dialog<bool>(AlertDialog(
                            title: const Text('Delete file?'),
                            content: Text('"${node.path}" will be removed.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Get.back(result: false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error),
                                onPressed: () => Get.back(result: true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ));
                          if (ok != true) return;
                          final ws = Get.find<AgentWorkspaceService>();
                          await ws.deleteFile(c.project.value!.id, node.path);
                          if (_openFile == node.path) {
                            setState(() => _openFile = null);
                          }
                          await c.notifyFilesChanged();
                        } else if (v == 'rename') {
                          showRenameDialog(context, isDark, node.path,
                              openFile: _openFile,
                              onPickFile: (p) => setState(() => _openFile = p));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename', style: TextStyle(fontSize: 14))),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(
                                    fontSize: 14, color: AppColors.error))),
                      ],
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      );

      if (node.isDir && isExpanded) {
        items.addAll(_renderTree(context, isDark, node.children, depth + 1));
      }
    }
    return items;
  }

  IconData _iconFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html') || p.endsWith('.htm')) {
      return LucideIcons.globe;
    }
    if (p.endsWith('.css')) return LucideIcons.palette;
    if (p.endsWith('.js') || p.endsWith('.jsx') || p.endsWith('.ts')) {
      return LucideIcons.fileCode2;
    }
    if (p.endsWith('.json')) return LucideIcons.braces;
    if (p.endsWith('.md')) return LucideIcons.fileText;
    if (p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.svg')) {
      return LucideIcons.image;
    }
    return LucideIcons.file;
  }

  List<String> _allFilePaths() {
    final out = [...c.files];
    for (final k in c.streamingFiles.keys) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  Widget _fileEditor(BuildContext context, bool isDark, String path) {
    if (c.streamingActive.value && c.streamingFiles.containsKey(path)) {
      return StreamingFileCard(path: path, isDark: isDark);
    }
    return FutureBuilder<String?>(
      key: ValueKey('editor-$path-${c.revision.value}'),
      future: c.readFile(path),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return FileEditorCard(
          key: ValueKey('card-$path'),
          path: path,
          initial: snap.data ?? '',
          isDark: isDark,
        );
      },
    );
  }
}

extension on AgentController {
  List<AgentProject> projectsOf() =>
      Get.find<AgentWorkspaceService>().projects.toList();
}
