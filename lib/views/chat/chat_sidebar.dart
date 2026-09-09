import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../core/colors.dart';
import '../../models/chat_session.dart';
import '../../services/hive_service.dart';
import '../../theme/design_tokens.dart';
import 'chat_dialogs.dart';
import 'chat_format.dart';

/// Chat history sidebar drawer.
/// Extracted from views/chat_view.dart.

class ChatSidebar extends StatefulWidget {
  final bool isDark;
  const ChatSidebar({super.key, required this.isDark});

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  ChatController get _c => Get.find<ChatController>();
  final RxString _sidebarQuery = ''.obs;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final RxSet<String> _searchHits = <String>{}.obs;
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
              _c.createNewChat();
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
            focusNode: _c.historySearchFocus,
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
          final showing = _c.showArchived.value;
          final n = _c.archivedCount;
          if (n == 0 && !showing) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _c.showArchived.value = !showing,
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
          final showing = _c.showHidden.value;
          final n = _c.hiddenCount;
          if (n == 0 && !showing) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _c.showHidden.value = !showing,
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
          final labels = _c.chatLabels;
          final active = _c.labelFilter.value;
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
                      onSelected: (_) => _c.labelFilter.value = '',
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
                          _c.labelFilter.value = active == l ? '' : l,
                    ),
                  ),
              ],
            ),
          );
        }),
        Expanded(
          child: Obx(() {
            // Read Rx first so the list tracks them (see NOTE above).
            final showA = _c.showArchived.value;
            final showH = _c.showHidden.value;
            final activeLabel = _c.labelFilter.value;
            var all = showA
                ? _c.sessions.toList()
                : _c.sessions.where((s) => !s.archived).toList();
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
                final active = _c.currentSessionId.value == s.id;
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
      onDismissed: (_) => _c.deleteChat(s.id),
      child: Material(
        color: active
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _c.openChat(s.id);
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
                  if (v == 'pin') _c.togglePin(s.id);
                  if (v == 'persona') showPersonaDialog(context, s, isDark);
                  if (v == 'archive') _c.toggleArchive(s.id);
                  if (v == 'hide') _c.toggleHidden(s.id);
                  if (v == 'lock') _c.toggleLocked(s.id);
                  if (v == 'label') showLabelDialog(context, s, isDark);
                  if (v == 'delete') _c.deleteChat(s.id);
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
}
