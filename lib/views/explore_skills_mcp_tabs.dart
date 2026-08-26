import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../models/skill_model.dart';
import '../services/mcp/mcp_config.dart';
import '../services/mcp/mcp_connection.dart';
import '../services/mcp/mcp_registry_service.dart';
import '../services/skills/github_skill_source.dart';
import '../services/skills/skill_registry_service.dart';
import '../services/skills/url_skill_source.dart';
import '../theme/design_tokens.dart';

// ── Explore Skills Tab ──

class ExploreSkillsTab extends StatelessWidget {
  const ExploreSkillsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final registry = Get.find<SkillRegistryService>();
    return Obx(() {
      final all = registry.skills.toList();
      final enabledCount = all.where((s) => s.enabled).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(LucideIcons.sparkles, size: 18, color: Dt.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Skills',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                      all.isEmpty
                          ? 'No skills yet — import one'
                          : '$enabledCount of ${all.length} enabled',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showImportOptions(context),
                icon: const Icon(LucideIcons.upload, size: 16),
                label: Text('Import',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            'Skills are offline instruction blocks appended to the system prompt. Enable any combination — they work for local and cloud models.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, height: 1.4, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 14),
          if (all.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline),
              ),
              child: Column(children: [
                Icon(LucideIcons.sparkles, size: 28, color: Theme.of(context).hintColor),
                const SizedBox(height: 8),
                Text('No skills installed',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Tap Import → From file / Browse GitHub / From URL',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: Theme.of(context).hintColor)),
              ]),
            )
          else
            for (final s in all) _skillTile(context, isDark, s),
        ],
      );
    });
  }

  Widget _skillTile(BuildContext context, bool isDark, SkillModel skill) {
    final registry = Get.find<SkillRegistryService>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: skill.enabled
                ? Dt.accent.withValues(alpha: 0.2)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: skill.enabled
                  ? Dt.accent.withValues(alpha: 0.15)
                  : Theme.of(context).hintColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                skill.isBuiltIn ? LucideIcons.award : LucideIcons.fileText,
                size: 18,
                color: skill.enabled ? Dt.accent : Theme.of(context).hintColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(skill.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700))),
                  if (skill.isBuiltIn)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('BUILT-IN',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: AppColors.info)),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Theme.of(context).hintColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(skill.source,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                        height: 1.3)),
                const SizedBox(height: 2),
                Text('${skill.author} · v${skill.version}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context).hintColor.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Switch(
                value: skill.enabled,
                activeThumbColor: Dt.accent,
                onChanged: (v) => v ? registry.enable(skill.id) : registry.disable(skill.id)),
            InkWell(
              onTap: () => _showPreview(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.eye, size: 18, color: Theme.of(context).hintColor)),
            ),
            InkWell(
              onTap: () => _confirmDelete(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.trash2, size: 18, color: AppColors.error.withValues(alpha: 0.8))),
            ),
          ]),
        ],
      ),
    );
  }

  void _showPreview(BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(skill.name, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${skill.author} · v${skill.version} · ${skill.source}',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 4),
          Text(skill.description,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
                child: Text(skill.content, style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4))),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Get.back(), child: const Text('Close'))],
    ));
  }

  void _confirmDelete(BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Delete skill?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text('Delete "${skill.name}"? This cannot be undone.', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              Get.find<SkillRegistryService>().delete(skill.id);
            },
            child: const Text('Delete')),
      ],
    ));
  }

  void _showImportOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
            color: isDark ? Dt.cardDark : Dt.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).hintColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Import Skill',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('All imports show a preview before saving.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          _importOptionTile(context, isDark,
              icon: LucideIcons.fileText,
              title: 'From file',
              subtitle: 'Pick a .md file from your device',
              onTap: () {
                Get.back();
                _importFromFile(context);
              }),
          _importOptionTile(context, isDark,
              icon: LucideIcons.github,
              title: 'Browse Anthropic skills',
              subtitle: 'Flat list from anthropics/skills on GitHub',
              onTap: () {
                Get.back();
                _browseGithub(context);
              }),
          _importOptionTile(context, isDark,
              icon: LucideIcons.link2,
              title: 'From URL',
              subtitle: 'Paste any direct link to a raw markdown file',
              onTap: () {
                Get.back();
                _importFromUrl(context);
              },
              showDivider: false),
        ]),
      ),
    );
  }

  Widget _importOptionTile(BuildContext context, bool isDark,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      bool showDivider = true}) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: Dt.accent)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Theme.of(context).hintColor, height: 1.3)),
            ])),
            Icon(LucideIcons.chevronRight, size: 18, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 1,
            indent: 50,
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
    ]);
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['md', 'markdown', 'txt'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String? content;
      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
      if (content == null || content.trim().isEmpty) {
        Get.snackbar('Import failed', 'File is empty', snackPosition: SnackPosition.BOTTOM);
        return;
      }
      String name = file.name.replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');
      name = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
      if (name.isEmpty) name = 'Imported Skill';
      if (!context.mounted) return;
      await _showImportPreview(context, content, initialName: name, source: 'file');
    } catch (e) {
      Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _browseGithub(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      _GithubBrowseSheetForExplore(isDark: isDark),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Future<void> _importFromUrl(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urlCtrl = TextEditingController();
    final urlOk = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import from URL', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Paste a direct link to a raw markdown file.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  hintText: 'https://raw.githubusercontent.com/.../SKILL.md',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
        ]),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () => Get.back(result: true),
              child: const Text('Fetch')),
        ],
      ),
    );
    final url = urlCtrl.text.trim();
    urlCtrl.dispose();
    if (urlOk != true || url.isEmpty) return;
    if (!context.mounted) return;
    Get.dialog(
      Center(
          child: Container(
              padding: const EdgeInsets.all(24),
              decoration:
                  BoxDecoration(color: isDark ? Dt.cardDark : Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: Dt.accent),
                const SizedBox(height: 12),
                Text('Fetching…', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              ]))),
      barrierDismissible: false,
    );
    try {
      final content = await UrlSkillSource().fetchFromUrl(url);
      if (!context.mounted) return;
      Get.back();
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = fm['name']?.isNotEmpty == true
          ? fm['name']!
          : Uri.tryParse(url)?.pathSegments.last
                  .replaceAll(RegExp(r'\.(md|markdown)$', caseSensitive: false), '')
                  .replaceAll(RegExp(r'[-_]+'), ' ')
                  .trim() ??
              'Imported Skill';
      final desc = fm['description'] ?? '';
      final author = fm['author'] ?? 'URL';
      await _showImportPreview(context, content,
          initialName: name, initialDesc: desc, initialAuthor: author, source: 'url');
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Fetch failed', '$e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.error, colorText: Colors.white);
    }
  }

  Future<void> _showImportPreview(BuildContext context, String content,
      {required String initialName,
      String initialDesc = '',
      String initialAuthor = 'User',
      String source = 'file'}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: initialName);
    final descCtrl = TextEditingController(text: initialDesc);
    final authorCtrl = TextEditingController(text: initialAuthor);
    final ok = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Skill', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 10),
            TextField(
                controller: authorCtrl,
                decoration: InputDecoration(
                    labelText: 'Author',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 14),
            Text('Preview — ${content.length} chars',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
              child: SingleChildScrollView(
                  child: Text(
                      content.length > 4000 ? '${content.substring(0, 4000)}\n…(truncated)' : content,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4))),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () => Get.back(result: true),
              child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      descCtrl.dispose();
      authorCtrl.dispose();
      return;
    }
    try {
      await Get.find<SkillRegistryService>().importFromMarkdown(content,
          name: nameCtrl.text, description: descCtrl.text, author: authorCtrl.text, source: source, enabled: true);
      Get.snackbar('Skill imported', nameCtrl.text.trim(),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.success, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
      authorCtrl.dispose();
    }
  }
}

class _GithubBrowseSheetForExplore extends StatefulWidget {
  final bool isDark;
  const _GithubBrowseSheetForExplore({required this.isDark});
  @override
  State<_GithubBrowseSheetForExplore> createState() => _GithubBrowseSheetForExploreState();
}

class _GithubBrowseSheetForExploreState extends State<_GithubBrowseSheetForExplore> {
  late Future<List<GithubSkillEntry>> _future;
  final _source = GithubSkillSource();
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GithubSkillEntry>> _load({bool force = false}) async {
    try {
      final list = await _source.listAvailable(forceRefresh: force);
      if (mounted) setState(() => _error = null);
      return list;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      rethrow;
    }
  }

  Future<void> _import(GithubSkillEntry entry) async {
    Get.dialog(
        Center(
            child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: widget.isDark ? Dt.cardDark : Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: Dt.accent),
                  const SizedBox(height: 12),
                  Text('Fetching ${entry.path}…', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ]))),
        barrierDismissible: false);
    try {
      final content = await _source.fetchSkillContent(entry.path);
      if (!mounted) return;
      Get.back();
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = entry.name.isNotEmpty ? entry.name : fm['name'] ?? entry.path.split('/').last;
      final desc = entry.description.isNotEmpty ? entry.description : fm['description'] ?? '';
      final ok = await Get.dialog<bool>(AlertDialog(
        backgroundColor: widget.isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Skill', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)),
          ],
          const SizedBox(height: 8),
          Text('From: ${entry.path} (untrusted text)',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                  child: Text(content.length > 4000 ? '${content.substring(0, 4000)}\n…(truncated)' : content,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4)))),
        ])),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () => Get.back(result: true),
              child: const Text('Import')),
        ],
      ));
      if (ok != true) return;
      await Get.find<SkillRegistryService>()
          .importFromMarkdown(content, name: name, description: desc, author: 'anthropics/skills', source: 'github', enabled: true);
      Get.snackbar('Skill imported', name,
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.success, colorText: Colors.white);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.error, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
          color: widget.isDark ? Dt.cardDark : Dt.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Browse Anthropic skills',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('anthropics/skills — flat list, no search',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
            ])),
            IconButton(
                onPressed: () async {
                  setState(() => _refreshing = true);
                  try {
                    final list = await _load(force: true);
                    setState(() {
                      _future = Future.value(list);
                      _refreshing = false;
                    });
                  } catch (_) {
                    setState(() => _refreshing = false);
                  }
                },
                icon: _refreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.refreshCw, size: 18)),
            IconButton(onPressed: () => Get.back(), icon: const Icon(LucideIcons.x, size: 20)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<GithubSkillEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Dt.accent));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,                   children: [
                    const Icon(LucideIcons.alertTriangle, size: 32, color: AppColors.warning),
                    const SizedBox(height: 12),
                    Text('Failed to load',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(_error ?? snap.error.toString(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () => setState(() => _future = _load(force: true)),
                        style: FilledButton.styleFrom(backgroundColor: Dt.accent),
                        child: const Text('Retry')),
                  ]),
                );
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('No skills found',
                        style: GoogleFonts.plusJakartaSans(color: Theme.of(context).hintColor)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 12,
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
                itemBuilder: (_, i) {
                  final e = list[i];
                  final alreadyInstalled = Get.find<SkillRegistryService>()
                      .skills
                      .any((s) => s.source == 'github' && s.name == e.name);
                  return ListTile(
                    leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(LucideIcons.sparkles, size: 18, color: Dt.accent)),
                    title: Text(e.name,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: e.description.isNotEmpty
                        ? Text(e.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor))
                        : Text(e.path,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                    trailing: alreadyInstalled
                        ? const Icon(LucideIcons.check, size: 18, color: AppColors.success)
                        : FilledButton(
                            onPressed: () => _import(e),
                            style: FilledButton.styleFrom(
                                backgroundColor: Dt.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: Text('Import',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Explore MCP Tab ──

class ExploreMcpTab extends StatefulWidget {
  const ExploreMcpTab({super.key});
  @override
  State<ExploreMcpTab> createState() => _ExploreMcpTabState();
}

class _ExploreMcpTabState extends State<ExploreMcpTab> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _inited = false;

  McpRegistryService get _reg => Get.find<McpRegistryService>();

  @override
  void initState() {
    super.initState();
    _reg.getToken().then((v) {
      if (mounted && v != null) _tokenCtrl.text = v;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool enable = false}) async {
    final name = _nameCtrl.text.trim().isEmpty ? 'Custom MCP' : _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      Get.snackbar('URL required', 'Please enter your MCP server URL', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      Get.snackbar('Invalid URL', 'Must be http(s)://…', snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _saving = true);
    try {
      await _reg.setToken(_tokenCtrl.text.trim());
      final cfg = _reg.config.value;
      final wasEnabled = cfg?.enabled ?? false;
      final shouldEnable = enable ? true : wasEnabled;
      final newCfg = McpConfig(
          name: name,
          url: url,
          transport: McpConfig.inferTransport(url),
          authType: _tokenCtrl.text.trim().isEmpty ? McpAuthType.none : McpAuthType.bearer,
          enabled: shouldEnable);
      await _reg.saveConfig(newCfg);
      Get.snackbar('Saved', 'MCP server ${shouldEnable ? 'enabled' : 'saved'}',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.success, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Save failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final cfg = _reg.config.value;
      final status = _reg.status.value;
      final tools = _reg.tools.toList();
      final err = _reg.lastError.value;
      if (!_inited && cfg != null) {
        _inited = true;
        _nameCtrl.text = cfg.name;
        _urlCtrl.text = cfg.url;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(color: Dt.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(LucideIcons.plug, size: 18, color: Dt.accent)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Custom MCP Server',
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800)),
                Text('One remote HTTP/SSE server — no marketplace',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
              ])),
              _statusDot(status),
            ]),
            const SizedBox(height: 12),
            _statusBanner(status, err, tools, isDark),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
          child: Column(children: [
            TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: 'Server name',
                    hintText: 'My MCP Server',
                    prefixIcon: const Icon(LucideIcons.tag, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 12),
            TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: 'Server URL (http/s)',
                    hintText: 'https://mcp.example.com/mcp',
                    prefixIcon: const Icon(LucideIcons.link2, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 12),
            TextField(
                controller: _tokenCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                    labelText: 'Bearer token (optional)',
                    hintText: 'Paste API key / token',
                    prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
                    suffixIcon: IconButton(
                        icon: Icon(_obscure ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true)),
            const SizedBox(height: 4),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Token stored in secure storage, never in Hive.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(),
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(_saving ? 'Saving…' : 'Save',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                          backgroundColor: Dt.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10)))),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () async {
                    await _save();
                    try {
                      await _reg.testConnection();
                      Get.snackbar('Connected', 'Server responded',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: AppColors.success,
                          colorText: Colors.white);
                    } catch (e) {
                      Get.snackbar('Connection failed', '$e',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: AppColors.error,
                          colorText: Colors.white,
                          duration: const Duration(seconds: 4));
                    }
                  },
                  icon: const Icon(LucideIcons.activity, size: 16),
                  label: Text('Test', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Dt.accent,
                      side: BorderSide(color: Dt.accent.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
            ]),
          ]),
        ),
        if (cfg != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
            child: Row(children: [
              Expanded(
                  child: Row(children: [
                Text('Enabled', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (tools.isNotEmpty && cfg.enabled && status == McpStatus.connected)
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text('${tools.length} tools',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success))),
              ])),
              Switch(
                  value: cfg.enabled,
                  activeThumbColor: Dt.accent,
                  onChanged: (v) async {
                    if (v && tools.isNotEmpty) {
                      final ok = await _confirmEnable(context, isDark, tools);
                      if (ok != true) return;
                    } else if (v) {
                      try {
                        final fetched = await _reg.connect();
                        if (context.mounted && fetched.isNotEmpty) {
                          final ok = await _confirmEnable(context, isDark, fetched);
                          if (ok != true) {
                            await _reg.disconnect();
                            return;
                          }
                        }
                      } catch (_) {}
                    }
                    final updated = cfg.copyWith(enabled: v);
                    await _reg.saveConfig(updated);
                    if (!v) await _reg.disconnect();
                  }),
            ]),
          ),
          if (cfg.enabled && status == McpStatus.connected && tools.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Exposed tools — model will see these',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
                const SizedBox(height: 8),
                for (final t in tools)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                                color: Dt.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(LucideIcons.wrench, size: 14, color: Dt.accent)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.name,
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                          if (t.description.isNotEmpty)
                            Text(t.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                        ])),
                      ])),
              ]),
            ),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await Get.dialog<bool>(AlertDialog(
                      backgroundColor: isDark ? Dt.cardDark : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text('Remove server?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                      content: Text('This will delete the URL and token.', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                      actions: [
                        TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
                        FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                            onPressed: () => Get.back(result: true),
                            child: const Text('Remove')),
                      ],
                    ));
                    if (ok == true) {
                      await _reg.removeConfig();
                      _nameCtrl.clear();
                      _urlCtrl.clear();
                      _tokenCtrl.clear();
                    }
                  },
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: Text('Remove server',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        ],
      ]);
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
                : null));
  }

  Widget _statusBanner(McpStatus status, String err, List<McpTool> tools, bool isDark) {
    final text = switch (status) {
      McpStatus.connected => tools.isEmpty ? 'Connected — no tools exposed' : 'Connected — ${tools.length} tool(s) ready',
      McpStatus.connecting => 'Connecting…',
      McpStatus.error => err.isNotEmpty ? err : 'Connection error',
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
            border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(children: [
          Icon(
              switch (status) {
                McpStatus.connected => LucideIcons.checkCircle,
                McpStatus.connecting => LucideIcons.loader2,
                McpStatus.error => LucideIcons.alertTriangle,
                McpStatus.disconnected => LucideIcons.info,
              },
              size: 16,
              color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
        ]));
  }

  Future<bool?> _confirmEnable(BuildContext context, bool isDark, List<McpTool> tools) {
    return Get.dialog<bool>(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Enable MCP tools?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('The model will be able to call these tools. Review them before enabling.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
        const SizedBox(height: 12),
        for (final t in tools)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(LucideIcons.wrench, size: 14, color: Dt.accent),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                  if (t.description.isNotEmpty)
                    Text(t.description,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                ])),
              ])),
      ])),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Enable')),
      ],
    ));
  }
}
