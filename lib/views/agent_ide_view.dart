import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../widgets/cli_sheets.dart';
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
  String _tab = 'preview'; // preview | files | terminal
  String? _openFile;
  String _viewport = 'full'; // full | desktop | tablet | mobile

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<AgentController>()
        ? Get.find<AgentController>()
        : Get.put(AgentController());
    // Rebuild ONLY this view on typing (focus node persists) so the send
    // button enables live — never write observables per keystroke.
    _askCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    // Also update send button when generation/fix state changes.
    ever(c.generating, (_) {
      if (mounted) setState(() {});
    });
    ever(c.fixing, (_) {
      if (mounted) setState(() {});
    });
    ever(c.project, (_) {
      if (mounted) setState(() {});
    });
    // Auto-open the first streaming file on the Files tab so the user
    // watches code appear without hunting for it.
    ever(c.streamingFiles, (_) {
      if (!mounted) return;
      if (_openFile == null && c.streamingFiles.isNotEmpty && _tab == 'files') {
        setState(() => _openFile = c.streamingFiles.keys.first);
      }
    });
    // Terminal input suggestions rebuild as the user types.
    _termCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(c.ensureTerminalWelcome());
    // Offer to adopt terminal-installed CLIs into the manager.
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

  @override
  void dispose() {
    _promptCtrl.dispose();
    _askCtrl.dispose();
    _askFocus.dispose();
    _termCtrl.dispose();
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
        // Cmd/Ctrl + Enter = send
        if (isMod && event.logicalKey == LogicalKeyboardKey.enter) {
          _sendFromAskBar();
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl + S = save current file
        if (isMod && event.logicalKey == LogicalKeyboardKey.keyS) {
          // Save is handled by the file editor's save button.
          return KeyEventResult.ignored;
        }
        // Cmd/Ctrl + 1/2/3 = switch tabs
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
          // Project identity lives IN the header: name + framework/files
          // once built, app title before that.
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
            // History + Auto-fix live in the header too (always visible,
            // dimmed until a project exists).
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
                          ? 'Pick mode on — long-press an element in preview'
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
            // CubicWeb System Logs in the main header (badge = unread).
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
            // Always visible: without a project the icon is dimmed and
            // project-dependent items are disabled.
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
          // ONE page, chat-style: the ask bar IS the input (prompt +
          // framework + send). No separate composer gate.
          final hasProject = c.project.value != null;
          // Wide screens (desktop/tablet landscape): IDE split — chat LEFT,
          // preview/files RIGHT side by side. Narrow keeps the tab switcher.
          final wide = MediaQuery.of(context).size.width >= 900 && hasProject;
          if (wide) {
            return Column(children: [
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
                            style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            segments: const [
                              ButtonSegment(
                                  value: 'preview',
                                  icon: Icon(LucideIcons.eye, size: 14)),
                              ButtonSegment(
                                  value: 'files',
                                  icon: Icon(LucideIcons.folderOpen, size: 14)),
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

  /// Framework picker sheet (no-project state only).

  /// Locked prompt summary on the project page: what was asked + which
  /// framework (read-only — the brief doesn't change mid-project).
  /// The + New button starts over (back to the composer on this same page).
  /// Reset to the empty composer (same reset the old summary card's
  /// "New" button performed). Safe anytime — pre-project it just clears.
  void _newProjectReset() {
    c.project.value = null;
    c.files.clear();
    c.previewUrl.value = null;
    c.transcript.clear();
    c.buildSteps.clear();
    _promptCtrl.clear();
  }

  // ── Header / tabs / ask ──

  // ── Viewport helpers ──

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

  /// Short label for the picked-element chip ("button · Buy now").
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

  /// Slim pane label for the wide IDE split (chat left, preview right).
  Widget _paneHeader(
      BuildContext context, bool isDark, String label, Widget? trailing) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
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
                letterSpacing: 1.1,
                color: Theme.of(context).hintColor)),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ]),
    );
  }

  double _viewportWidth() {
    switch (_viewport) {
      case 'mobile':
        return 375;
      case 'tablet':
        return 768;
      case 'desktop':
        return 1024;
      default:
        return double.infinity;
    }
  }

  Widget _viewportBtn(String mode, IconData icon, String label, bool isDark) {
    final active = _viewport == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewport = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Dt.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon,
            size: 13, color: active ? Dt.accent : Theme.of(context).hintColor),
      ),
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
                  // ── Text field: full-width, ABOVE the controls row ──
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
                  // ── Screenshot chip (attachment preview) ──
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
                  // Picked-element chip (visual edit context)
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
                  // ── Controls row: + / model pill / tools … send ──
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    // "+" — builder tools live here (left side).
                    AppCircleButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Builder tools',
                      onTap: () => showBuilderToolsSheet(
                          context, isDark, hasProject,
                          askCtrl: _askCtrl,
                          onInserted: () => _askFocus.requestFocus()),
                    ),
                    const SizedBox(width: 8),
                    // Model selector pill — under the box, not in header.
                    SizedBox(
                      width: 125,
                      child: Obx(() => AppModelPill(
                            label: builderModelLabel(),
                            onTap: () => showModelSwitcherSheet(context),
                          )),
                    ),
                    const SizedBox(width: 6),
                    // Scrollable tools strip — never squeezes the field.
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
                          // Shared tools — identical before AND after build. Only
                          // Auto-test needs a project (dimmed + disabled until then).
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

  // ── Preview pane ──

  /// Slim progress pill shown ABOVE the live preview while the AI keeps
  /// writing (v0-style: preview stays visible, progress floats on top).
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

  /// Runtime diagnosis card: what kind of project this is, which
  /// pipeline steps passed/failed, and specific fix actions.
  /// Hidden for plain static sites (nothing to explain there).
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
    // While working, the preview area shows LIVE progress (files being
    // written, tool calls) — once the project structure is complete it
    // swaps to the rendered output. Never a dead spinner.
    final status = c.buildStatus.value;
    final working = c.generating.value || c.fixing.value || status != null;
    // v0-style live preview: once partial files hit disk, keep the
    // WebView up and reloading instead of hiding it behind a spinner.
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
    return Column(children: [
      _previewDiagnosisCard(context, isDark),
      if (working) _liveProgressPill(context, isDark, status),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          Expanded(
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(
                    fontSize: 10.5, color: Theme.of(context).hintColor)),
          ),
          Obx(() => c.devServerUrl.value != null
              ? Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF4ADE80))),
                    const SizedBox(width: 4),
                    Text('LIVE',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF4ADE80))),
                  ]),
                )
              : const SizedBox.shrink()),
          // Viewport toggle
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(7),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _viewportBtn('full', LucideIcons.monitor, 'Full', isDark),
              _viewportBtn('desktop', LucideIcons.monitor, 'Desktop', isDark),
              _viewportBtn('tablet', LucideIcons.tablet, 'Tablet', isDark),
              _viewportBtn('mobile', LucideIcons.smartphone, 'Mobile', isDark),
            ]),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => setState(() => _reloadNonce++),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(LucideIcons.rotateCw, size: 15),
            ),
          ),
          InkWell(
            onTap: () async {
              final u = c.previewUrl.value;
              if (u == null || u.isEmpty) return;
              try {
                await launchUrl(Uri.parse(u),
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(LucideIcons.externalLink, size: 15),
            ),
          ),
          InkWell(
            onTap: () => c.capturePreviewShot(),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Tooltip(
                message: 'Capture screenshot as AI context',
                child: Icon(LucideIcons.camera, size: 15),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        flex: 3,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _viewportWidth(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Obx(() => AgentPreview(
                    key: ValueKey(
                        'agent-$revision-$url-$_reloadNonce-$_viewport'),
                    url: url,
                    onConsoleError: (msg) => c.onConsoleError(msg),
                    pickMode: c.elementPickMode.value,
                    onElementPicked: (info) => c.onElementPicked(info),
                  )),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        flex: 2,
        child: _terminalStrip(context),
      ),
    ]);
  }

  /// Terminal lives UNDER preview (not a separate tab): build output,
  /// file writes, console errors — the same buffer the AI repairs from.
  Widget _terminalStrip(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.terminal, size: 13, color: Dt.accent),
          const SizedBox(width: 6),
          Text('TERMINAL',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: const Color(0xFF9A958C))),
          const Spacer(),
          Obx(() => c.activeCliId.value == null
              ? const SizedBox.shrink()
              : InkWell(
                  onTap: () => c.stopActiveCli(),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(LucideIcons.square,
                        size: 13, color: AppColors.error),
                  ),
                )),
          InkWell(
            onTap: () => showCliManagerSheet(context),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(LucideIcons.package, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
          InkWell(
            onTap: () => showRecentCommandsSheet(context, (cmd) {
              _termCtrl.text = cmd;
            }),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(LucideIcons.history, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
          InkWell(
            onTap: () => c.askAiToFixTerminalError(),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(LucideIcons.wand2, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
          InkWell(
            onTap: () =>
                Clipboard.setData(ClipboardData(text: c.terminal.join('\n'))),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(LucideIcons.copy, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
          InkWell(
            onTap: () {
              final text = c.terminal.join('\n');
              if (text.trim().isEmpty) return;
              Share.share(text, subject: 'CubicLM terminal log');
            },
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(LucideIcons.share2, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
          InkWell(
            onTap: c.clearTerminal,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(LucideIcons.trash2, size: 13, color: Color(0xFF9A958C)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: Obx(() {
            if (c.terminal.isEmpty) {
              return Text(
                '\$ builds, fixes and errors appear here',
                style: GoogleFonts.firaCode(
                    fontSize: 11, color: const Color(0xFF6E6B65)),
              );
            }
            final lines = c.terminal.toList();
            final tail =
                lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
            return ListView.builder(
              itemCount: tail.length,
              itemBuilder: (_, i) => SelectableText(
                tail[i],
                style: GoogleFonts.firaCode(
                    fontSize: 10.5, height: 1.5, color: _termColor(tail[i])),
              ),
            );
          }),
        ),
        // ── Attached CLI banner (input routes to its stdin) ──
        Obx(() {
          final id = c.activeCliId.value;
          if (id == null) return const SizedBox.shrink();
          String name = id;
          try {
            name =
                Get.find<CliManagerService>().manifestById(id)?.displayName ??
                    id;
          } catch (_) {}
          return Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Dt.accent)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    '$name attached — input goes to the CLI (!cmd runs shell)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        GoogleFonts.firaCode(fontSize: 10.5, color: Dt.accent)),
              ),
              InkWell(
                onTap: () => c.stopActiveCli(),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(LucideIcons.square,
                      size: 12, color: AppColors.error),
                ),
              ),
            ]),
          );
        }),
        // ── Autocomplete (installed CLIs + recent, non-intrusive) ──
        Builder(builder: (_) {
          List<String> sug = const [];
          try {
            final attached = c.activeCliId.value != null;
            if (!attached && _termCtrl.text.trim().isNotEmpty) {
              sug =
                  Get.find<CliManagerService>().suggestCommands(_termCtrl.text);
            }
          } catch (_) {}
          if (sug.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in sug)
                  InkWell(
                    onTap: () {
                      _termCtrl.text = s.endsWith(' ') ? s : '$s ';
                      _termCtrl.selection = TextSelection.collapsed(
                          offset: _termCtrl.text.length);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(
                              fontSize: 10.5, color: const Color(0xFF89DCEB))),
                    ),
                  ),
              ],
            ),
          );
        }),
        // ── Real shell input: runs in the project dir, streams output ──
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Obx(() => Text(c.activeCliId.value == null ? '\$' : '›',
                style: GoogleFonts.firaCode(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Dt.accent))),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _termCtrl,
                style: GoogleFonts.firaCode(
                    fontSize: 11.5, color: const Color(0xFFCDD6F4)),
                decoration: InputDecoration(
                  hintText: 'node --version · npm install · ls …',
                  hintStyle: GoogleFonts.firaCode(
                      fontSize: 11, color: const Color(0xFF6E6B65)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => _submitTermInput(),
              ),
            ),
            InkWell(
              onTap: _submitTermInput,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(LucideIcons.cornerDownLeft,
                    size: 14, color: Dt.accent),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Route terminal input: attached CLI gets stdin, `!cmd` (or no
  /// attachment) runs a real one-shot shell command.
  void _submitTermInput() {
    final v = _termCtrl.text;
    _termCtrl.clear();
    if (v.trim().isEmpty) return;
    final attached = c.activeCliId.value != null;
    if (attached && !v.trimLeft().startsWith('!')) {
      c.sendStdinToCli(v);
    } else {
      c.runShellCommand(attached ? v.trimLeft().substring(1) : v);
    }
  }

  /// Live build/progress view: what the AI is doing RIGHT NOW
  /// (streaming, files, tool calls) — with per-file ticks.
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

  int _reloadNonce = 0;

  /// Conversation with the builder AI (prompts + summaries).

  Widget _chatPane(BuildContext context, bool isDark) {
    return Obx(() {
      final planPending = c.pendingPlan.value != null;
      final hasDiffs = c.lastDiffs.isNotEmpty;
      final showSteps = c.buildSteps.isNotEmpty;
      final extraItems =
          (planPending ? 1 : 0) + (hasDiffs ? 1 : 0) + (showSteps ? 1 : 0);
      final itemCount = c.transcript.length + extraItems;
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          var idx = i;
          // Live build activity — always first.
          if (showSteps) {
            if (idx == 0) return activityCard(context, isDark);
            idx -= 1;
          }
          // Diff card — after all transcript + plan
          if (hasDiffs && idx == c.transcript.length + (planPending ? 1 : 0)) {
            return diffCard(context, isDark);
          }
          // Plan card — after transcript
          if (planPending && idx == c.transcript.length) {
            return planCard(context, isDark);
          }
          final m = c.transcript[idx];
          final user = m['role'] == 'user';
          return Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82),
              decoration: BoxDecoration(
                color: user
                    ? Dt.accent
                    : (isDark ? AppColors.surface : const Color(0xFFF1EFE9)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                m['text'] ?? '',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.45,
                    color: user
                        ? Colors.white
                        : (isDark ? AppColors.textPrimary : Dt.textPrimary)),
              ),
            ),
          );
        },
      );
    });
  }

  // ── Split Pane ──

  Widget _splitOrPreview(BuildContext context, bool isDark) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!isLandscape) {
      return _previewPane(context, isDark, c.revision.value);
    }
    // Landscape: preview (left) + files (right) side by side.
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

  // ── Templates ──

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
    // Scrollable: inside Center the height is unbounded, so a fixed
    // Column + grid would overflow on short screens / large text.
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
                  // Fill the prompt only — framework stays as the user
                  // picked it (no silent override).
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

  // ── Files pane ──

  /// Terminal: agent activity stream. Read-only by design (no shell on
  /// stock Android) — but the AI reads this same buffer in repair
  /// prompts, so errors here directly drive fixes.
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Obx(() {
              final extra = c.streamingFiles.keys
                  .where((k) => !c.files.contains(k))
                  .length;
              final total = c.files.length + extra;
              return Text(
                  extra > 0 ? '$total files ($extra writing…)' : '$total files',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).hintColor));
            }),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onSubmitted: (q) => showSearchResults(context, isDark, q,
              onPickFile: (p) => setState(() => _openFile = p)),
        ),
        const SizedBox(height: 8),
        for (final path in _allFilePaths())
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(_iconFor(path), size: 18, color: Dt.accent),
              title: Row(children: [
                Expanded(
                  child: Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                ),
                Obx(() => c.streamingFiles.containsKey(path)
                    ? Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Dt.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle, color: Dt.accent)),
                          const SizedBox(width: 4),
                          Text('writing',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Dt.accent)),
                        ]),
                      )
                    : const SizedBox.shrink()),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Open',
                  icon: const Icon(LucideIcons.chevronRight, size: 18),
                  onPressed: () => setState(() => _openFile = path),
                ),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(LucideIcons.pencil, size: 15),
                  onPressed: () => showRenameDialog(context, isDark, path,
                      openFile: _openFile,
                      onPickFile: (p) => setState(() => _openFile = p)),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(LucideIcons.trash2,
                      size: 16, color: AppColors.error.withValues(alpha: 0.8)),
                  onPressed: () async {
                    final ok = await Get.dialog<bool>(AlertDialog(
                      title: const Text('Delete file?'),
                      content: Text('"$path" will be removed.'),
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
                    await ws.deleteFile(c.project.value!.id, path);
                    if (_openFile == path) {
                      setState(() => _openFile = null);
                    }
                    await c.notifyFilesChanged();
                  },
                ),
              ]),
              onTap: () =>
                  setState(() => _openFile = _openFile == path ? null : path),
            ),
          ),
        if (_openFile != null &&
            (c.files.contains(_openFile) ||
                c.streamingFiles.containsKey(_openFile))) ...[
          const SizedBox(height: 8),
          _fileEditor(context, isDark, _openFile!),
        ],
      ],
    );
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

  /// Disk files + in-flight streamed files, disk order first.
  List<String> _allFilePaths() {
    final out = [...c.files];
    for (final k in c.streamingFiles.keys) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  Widget _fileEditor(BuildContext context, bool isDark, String path) {
    // While the AI is writing this file, show the LIVE stream instead
    // of a stale disk read (tap in and watch the code appear).
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
