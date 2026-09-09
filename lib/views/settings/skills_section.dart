import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/colors.dart';
import '../../models/skill_model.dart';
import '../../services/skills/github_skill_source.dart';
import '../../services/skills/skill_registry_service.dart';
import '../../services/skills/url_skill_source.dart';
import '../../theme/design_tokens.dart';
import 'apple_widgets.dart';

/// Skills section + import/preview/delete flows.
/// Extracted from views/settings_view.dart.
// ── Skills ──
Widget buildSkillsSection(BuildContext context, bool isDark) {
  final registry = Get.find<SkillRegistryService>();
  return Obx(() {
    final all = registry.skills.toList();
    final enabledCount = all.where((s) => s.enabled).length;
    return appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(children: [
          iconBox(Dt.accent, LucideIcons.sparkles),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Skills',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  all.isEmpty
                      ? 'No skills installed'
                      : '$enabledCount of ${all.length} enabled — appended to system prompt',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => showImportOptions(context),
            icon: const Icon(LucideIcons.upload, size: 16),
            label: Text('Import',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 36),
            ),
          ),
        ]),
      ),
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Skills are offline instruction blocks that teach the model how to handle certain tasks. Import a .md file or enable a built-in skill.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, height: 1.4, color: Theme.of(context).hintColor),
          ),
        )
      else
        for (var i = 0; i < all.length; i++) ...[
          Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: isDark
                  ? AppColors.border.withValues(alpha: 0.5)
                  : AppColors.borderLightMode.withValues(alpha: 0.5)),
          skillTile(context, isDark, all[i]),
        ],
      const SizedBox(height: 8),
    ]);
  });
}

Widget skillTile(BuildContext context, bool isDark, SkillModel skill) {
  final registry = Get.find<SkillRegistryService>();
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            color: skill.enabled ? Dt.accent : Theme.of(context).hintColor,
          ),
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
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (skill.isBuiltIn)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('BUILT-IN',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppColors.info)),
                  ),
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).hintColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
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
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 2),
              Text('${skill.author} · v${skill.version}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color:
                          Theme.of(context).hintColor.withValues(alpha: 0.8))),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(children: [
          Switch(
            value: skill.enabled,
            activeThumbColor: Dt.accent,
            onChanged: (v) =>
                v ? registry.enable(skill.id) : registry.disable(skill.id),
          ),
          InkWell(
            onTap: () => showSkillPreview(context, isDark, skill),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(LucideIcons.eye,
                  size: 18, color: Theme.of(context).hintColor),
            ),
          ),
          if (!skill.isBuiltIn || true)
            InkWell(
              onTap: () => confirmDeleteSkill(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.trash2,
                    size: 18, color: AppColors.error.withValues(alpha: 0.8)),
              ),
            ),
        ]),
      ],
    ),
  );
}

Future<void> _importSkillFromFile(BuildContext context) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String? content;
    if (file.bytes != null) {
      content = String.fromCharCodes(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null || content.trim().isEmpty) {
      Get.snackbar('Import failed', 'File is empty',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    // Derive name from filename.
    String name = file.name
        .replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (name.isEmpty) name = 'Imported Skill';
    // Show preview/confirm dialog before saving.
    if (!context.mounted) return;
    await _showImportPreview(context, content, initialName: name);
  } catch (e) {
    Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
  }
}

void showImportOptions(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Import Skill',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Choose a source — all imports show a preview before saving.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  height: 1.4)),
          const SizedBox(height: 16),
          importOptionTile(
            context,
            isDark,
            icon: LucideIcons.fileText,
            title: 'From file',
            subtitle: 'Pick a .md file from your device',
            onTap: () {
              Get.back();
              _importSkillFromFile(context);
            },
          ),
          importOptionTile(
            context,
            isDark,
            icon: LucideIcons.github,
            title: 'Browse Anthropic skills',
            subtitle: 'Flat list from anthropics/skills on GitHub',
            onTap: () {
              Get.back();
              _browseGithubSkills(context);
            },
          ),
          importOptionTile(
            context,
            isDark,
            icon: LucideIcons.link2,
            title: 'From URL',
            subtitle: 'Paste any direct link to a raw markdown file',
            onTap: () {
              Get.back();
              _importFromUrl(context);
            },
            showDivider: false,
          ),
        ],
      ),
    ),
    isScrollControlled: false,
  );
}

Widget importOptionTile(
  BuildContext context,
  bool isDark, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  bool showDivider = true,
}) {
  return Column(children: [
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          iconBox(Dt.accent, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                        height: 1.3)),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight,
              size: 18, color: Theme.of(context).hintColor),
        ]),
      ),
    ),
    if (showDivider)
      Divider(
          height: 1,
          indent: 50,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06)),
  ]);
}

Future<void> _browseGithubSkills(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final source = GithubSkillSource();
  // Show loading sheet first.
  Get.bottomSheet(
    GithubBrowseSheet(source: source, isDark: isDark),
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
      title: Text('Import from URL',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paste a direct link to a raw markdown file.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          TextField(
            controller: urlCtrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://raw.githubusercontent.com/.../SKILL.md',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common_cancel'.tr)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Dt.accent),
          onPressed: () => Get.back(result: true),
          child: const Text('Fetch'),
        ),
      ],
    ),
  );
  final url = urlCtrl.text.trim();
  urlCtrl.dispose();
  if (urlOk != true || url.isEmpty) return;
  if (!context.mounted) return;
  // Show loading.
  Get.dialog(
    Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Dt.accent),
          const SizedBox(height: 16),
          Text('Fetching…',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
    barrierDismissible: false,
  );
  try {
    final content = await UrlSkillSource().fetchFromUrl(url);
    if (!context.mounted) return;
    Get.back(); // close loading
    final fm = UrlSkillSource.parseFrontmatter(content);
    final name = fm['name']?.isNotEmpty == true
        ? fm['name']!
        : Uri.tryParse(url)
                ?.pathSegments
                .last
                .replaceAll(
                    RegExp(r'\.(md|markdown)$', caseSensitive: false), '')
                .replaceAll(RegExp(r'[-_]+'), ' ')
                .trim() ??
            'Imported Skill';
    final desc = fm['description'] ?? '';
    final author = fm['author'] ?? 'URL';
    // Reuse preview dialog but with url source.
    await _showUrlPreview(context, content,
        initialName: name, initialDesc: desc, initialAuthor: author);
  } catch (e) {
    Get.back(); // close loading if still open
    if (Get.isDialogOpen ?? false) Get.back();
    Get.snackbar('Fetch failed', '$e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.error,
        colorText: Colors.white);
  }
}

Future<void> _showUrlPreview(BuildContext context, String content,
    {required String initialName,
    String initialDesc = '',
    String initialAuthor = 'URL'}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final nameCtrl = TextEditingController(text: initialName);
  final descCtrl = TextEditingController(text: initialDesc);
  final authorCtrl = TextEditingController(text: initialAuthor);
  final previewOk = await Get.dialog<bool>(
    AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Import Skill',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorCtrl,
              decoration: InputDecoration(
                labelText: 'Author',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text('Preview — ${content.length} chars (untrusted text)',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Dt.pillMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Dt.hairline),
              ),
              child: SingleChildScrollView(
                child: Text(
                  content.length > 4000
                      ? '${content.substring(0, 4000)}\n…(truncated)'
                      : content,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
                ),
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
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (previewOk != true) {
    nameCtrl.dispose();
    descCtrl.dispose();
    authorCtrl.dispose();
    return;
  }
  try {
    final registry = Get.find<SkillRegistryService>();
    await registry.importFromMarkdown(
      content,
      name: nameCtrl.text,
      description: descCtrl.text,
      author: authorCtrl.text,
      source: 'url',
      enabled: true,
    );
    Get.snackbar('Skill imported', nameCtrl.text.trim(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.success,
        colorText: Colors.white);
  } catch (e) {
    Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
  } finally {
    nameCtrl.dispose();
    descCtrl.dispose();
    authorCtrl.dispose();
  }
}

Future<void> _showImportPreview(BuildContext context, String content,
    {required String initialName}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final nameCtrl = TextEditingController(text: initialName);
  final descCtrl = TextEditingController();
  final authorCtrl = TextEditingController(text: 'User');
  final previewOk = await Get.dialog<bool>(
    AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Import Skill',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorCtrl,
              decoration: InputDecoration(
                labelText: 'Author',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text('Preview — ${content.length} chars',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Dt.pillMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Dt.hairline),
              ),
              child: SingleChildScrollView(
                child: Text(
                  content.length > 4000
                      ? '${content.substring(0, 4000)}\n…(truncated)'
                      : content,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
                ),
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
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (previewOk != true) return;
  try {
    final registry = Get.find<SkillRegistryService>();
    await registry.importFromMarkdown(
      content,
      name: nameCtrl.text,
      description: descCtrl.text,
      author: authorCtrl.text,
      source: 'file',
      enabled: true,
    );
    Get.snackbar('Skill imported', nameCtrl.text.trim(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.success,
        colorText: Colors.white);
  } catch (e) {
    Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
  } finally {
    nameCtrl.dispose();
    descCtrl.dispose();
    authorCtrl.dispose();
  }
}

void showSkillPreview(BuildContext context, bool isDark, SkillModel skill) {
  Get.dialog(
    AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(skill.name,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${skill.author} · v${skill.version} · ${skill.source}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 4),
            Text(skill.description,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Dt.pillMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(skill.content,
                    style:
                        GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Close')),
      ],
    ),
  );
}

void confirmDeleteSkill(BuildContext context, bool isDark, SkillModel skill) {
  Get.dialog(
    AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Delete skill?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text('Delete "${skill.name}"? This cannot be undone.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: Text('common_cancel'.tr)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () {
            Get.back();
            Get.find<SkillRegistryService>().delete(skill.id);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

class GithubBrowseSheet extends StatefulWidget {
  final GithubSkillSource source;
  final bool isDark;
  const GithubBrowseSheet(
      {super.key, required this.source, required this.isDark});

  @override
  State<GithubBrowseSheet> createState() => GithubBrowseSheetState();
}

class GithubBrowseSheetState extends State<GithubBrowseSheet> {
  late Future<List<GithubSkillEntry>> _future;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GithubSkillEntry>> _load({bool force = false}) async {
    try {
      final list = await widget.source.listAvailable(forceRefresh: force);
      setState(() => _error = null);
      return list;
    } catch (e) {
      setState(() => _error = e.toString());
      rethrow;
    }
  }

  Future<void> _import(GithubSkillEntry entry) async {
    Get.dialog(
      Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.isDark ? Dt.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Dt.accent),
            const SizedBox(height: 12),
            Text('Fetching ${entry.path}…',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
          ]),
        ),
      ),
      barrierDismissible: false,
    );
    try {
      final content = await widget.source.fetchSkillContent(entry.path);
      if (!mounted) return;
      Get.back();
      // Show preview using same dialog as file import but with github source.
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = entry.name.isNotEmpty
          ? entry.name
          : fm['name'] ?? entry.path.split('/').last;
      final desc = entry.description.isNotEmpty
          ? entry.description
          : fm['description'] ?? '';
      // Reuse the preview dialog from SettingsView by delegating to registry directly.
      final previewOk = await Get.dialog<bool>(
        AlertDialog(
          backgroundColor: widget.isDark ? Dt.cardDark : Dt.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Import Skill',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).hintColor)),
                ],
                const SizedBox(height: 8),
                Text('From: ${entry.path} (untrusted text)',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Theme.of(context).hintColor)),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Dt.pillMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      content.length > 4000
                          ? '${content.substring(0, 4000)}\n…(truncated)'
                          : content,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, height: 1.4),
                    ),
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
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (previewOk != true) return;
      await Get.find<SkillRegistryService>().importFromMarkdown(
        content,
        name: name,
        description: desc,
        author: 'anthropics/skills',
        source: 'github',
        enabled: true,
      );
      Get.snackbar('Skill imported', name,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success,
          colorText: Colors.white);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.error,
          colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: widget.isDark ? Dt.cardDark : Dt.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).hintColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Browse Anthropic skills',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('anthropics/skills — flat list, no search',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          height: 1.3)),
                ],
              ),
            ),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.refreshCw, size: 18),
            ),
            IconButton(
              onPressed: () => Get.back(),
              icon: const Icon(LucideIcons.x, size: 20),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<GithubSkillEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Dt.accent));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          size: 32, color: AppColors.warning),
                      const SizedBox(height: 12),
                      Text('Failed to load',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_error ?? snap.error.toString(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context).hintColor)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _future = _load(force: true)),
                        style:
                            FilledButton.styleFrom(backgroundColor: Dt.accent),
                        child: const Text('Retry'),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Showing cached list if available.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor)),
                        ),
                    ],
                  ),
                );
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                  child: Text('No skills found',
                      style: GoogleFonts.plusJakartaSans(
                          color: Theme.of(context).hintColor)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 12,
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06)),
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
                        color: Dt.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.sparkles,
                          size: 18, color: Dt.accent),
                    ),
                    title: Text(e.name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: e.description.isNotEmpty
                        ? Text(e.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context).hintColor))
                        : Text(e.path,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor)),
                    trailing: alreadyInstalled
                        ? const Icon(LucideIcons.check,
                            size: 18, color: AppColors.success)
                        : FilledButton(
                            onPressed: () => _import(e),
                            style: FilledButton.styleFrom(
                              backgroundColor: Dt.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Import',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
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
