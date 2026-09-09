import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/agent_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../services/deploy_service.dart';
import '../../services/inference_service.dart';
import '../../services/local_image_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/web_project.dart';
import '../../widgets/model_switcher_sheet.dart';
import 'file_cards.dart';

/// Project sheets, menus, deploy/share flows for the Agent IDE.
/// Extracted from views/agent_ide_view.dart.

AgentController get _c => Get.find<AgentController>();

/// Short framework label (shared with the ask row).
String frameworkShort(String f) {
  if (f == 'Single HTML') {
    return 'HTML';
  }
  if (f == 'HTML + CSS + JS') {
    return 'Trio';
  }
  if (f.startsWith('React')) {
    return 'React';
  }
  if (f.startsWith('Next')) {
    return 'Next';
  }
  if (f.startsWith('Vue')) {
    return 'Vue';
  }
  return f.length > 8 ? f.substring(0, 8) : f;
}

void showHistorySheet(BuildContext context) async {
  final p = _c.project.value;
  if (p == null) return;
  final checkpoints =
      await Get.find<AgentWorkspaceService>().listCheckpoints(p.id);
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text('History',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Text('${checkpoints.length} snapshots',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Theme.of(context).hintColor)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: checkpoints.isEmpty
                ? Center(
                    child: Text(
                        'No checkpoints yet.\nSnapshots are saved automatically before each build.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: Theme.of(context).hintColor)),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: checkpoints.length,
                    itemBuilder: (_, i) {
                      final cp = checkpoints[i];
                      final dt =
                          DateTime.fromMillisecondsSinceEpoch(cp.timestampMs);
                      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:'
                          '${dt.minute.toString().padLeft(2, '0')}';
                      final dateStr = '${dt.month}/${dt.day} $timeStr';
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          i == 0 ? LucideIcons.dot : LucideIcons.history,
                          size: 16,
                          color:
                              i == 0 ? Dt.accent : Theme.of(context).hintColor,
                        ),
                        title: Text(cp.label,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: i == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        subtitle: Text('$dateStr · ${cp.fileCount} files',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor)),
                        trailing: i == 0
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  final count =
                                      await Get.find<AgentWorkspaceService>()
                                          .rollbackToCheckpoint(p.id, cp.id);
                                  await _c.refreshFiles();
                                  _c.revision.value++;
                                  AppSnackbar.showTop(
                                    'Rolled back',
                                    '$count files restored from "${cp.label}"',
                                  );
                                },
                                child: Text('Restore',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}

Future<void> onProjectMenu(BuildContext context, String v,
    {required TextEditingController promptCtrl}) async {
  if (v == 'new') {
    _c.project.value = null;
    _c.files.clear();
    _c.previewUrl.value = null;
    promptCtrl.clear();
  } else if (v == 'export') {
    await _c.exportZip();
  } else if (v == 'rename') {
    final p = _c.project.value;
    if (p == null) return;
    final nameCtrl = TextEditingController(text: p.name);
    final next = await Get.dialog<String>(AlertDialog(
      title: const Text('Rename project'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name', isDense: true),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: null),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Get.back(result: nameCtrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ));
    if (next != null && next.isNotEmpty) {
      await _c.renameProject(next);
    }
  } else if (v == 'fork') {
    await _c.forkProject();
  } else if (v == 'delete') {
    final p = _c.project.value;
    if (p == null) return;
    final ok = await Get.dialog<bool>(AlertDialog(
      title: const Text('Delete project?'),
      content: Text('"${p.name}" and all its files will be removed.'),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Get.back(result: true),
          child: const Text('Delete'),
        ),
      ],
    ));
    if (ok == true) {
      await _c.deleteProject(p.id);
      promptCtrl.clear();
    }
  } else if (v == 'switch') {
    showProjectSwitcher(context);
  } else if (v == 'deploy') {
    showDeploySheet(context);
  } else if (v == 'share') {
    shareProjectLink(context);
  } else if (v == 'github') {
    exportToGitHub(context);
  }
}

void showProjectSwitcher(BuildContext context) {
  final ws = Get.find<AgentWorkspaceService>();
  ws.loadProjects();
  showModalBottomSheet(
    context: context,
    builder: (_) => Obx(() => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in ws.projects)
                ListTile(
                  leading: const Icon(LucideIcons.folderGit2, size: 20),
                  title: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(p.framework,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: Theme.of(context).hintColor)),
                  trailing: _c.project.value?.id == p.id
                      ? const Icon(LucideIcons.check,
                          size: 18, color: Dt.accent)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _c.openProject(p);
                  },
                ),
              if (ws.projects.isEmpty)
                const ListTile(title: Text('No projects yet.')),
            ],
          ),
        )),
  );
}

void showDeploySheet(BuildContext context) {
  final p = _c.project.value;
  if (p == null) return;
  final files = _c.files;
  if (files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Build the project first before deploying.')),
    );
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final tokenCtrl = TextEditingController();
      String provider = 'vercel';
      bool deploying = false;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deploy "${p.name}"',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Row(children: [
                  ChoiceChip(
                    label: const Text('Vercel'),
                    selected: provider == 'vercel',
                    onSelected: (_) => setSheet(() => provider = 'vercel'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Netlify'),
                    selected: provider == 'netlify',
                    onSelected: (_) => setSheet(() => provider = 'netlify'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: provider == 'vercel'
                        ? 'Vercel API Token'
                        : 'Netlify Personal Access Token',
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.key, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                if (deploying) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: deploying
                        ? null
                        : () async {
                            if (tokenCtrl.text.trim().isEmpty) return;
                            setSheet(() => deploying = true);
                            try {
                              // Read file contents from workspace.
                              final ws = Get.find<AgentWorkspaceService>();
                              final fileMap = <String, String>{};
                              for (final f in files) {
                                final content = await ws.readFile(p.id, f);
                                if (content != null) fileMap[f] = content;
                              }
                              if (fileMap.isEmpty) {
                                throw Exception(
                                    'No files to deploy. Build the project first.');
                              }
                              final result =
                                  await Get.find<DeployService>().deploy(
                                provider: provider,
                                token: tokenCtrl.text.trim(),
                                projectName: p.name,
                                files: fileMap,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              // Show success URL.
                              Get.dialog(AlertDialog(
                                title: Text('Deployed to $provider!'),
                                content: SelectableText(result.url,
                                    style: GoogleFonts.firaCode(fontSize: 13)),
                                actions: [
                                  FilledButton(
                                    onPressed: () => Get.back(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ));
                            } catch (e) {
                              setSheet(() => deploying = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Deploy failed: $e')),
                                );
                              }
                            }
                          },
                    icon: const Icon(LucideIcons.upload, size: 18),
                    label: const Text('Deploy'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void showComponentLibrary(BuildContext context, bool isDark,
    {required TextEditingController askCtrl,
    required VoidCallback onInserted}) {
  final components = [
    const WebComponent(
        'Navbar', LucideIcons.menu, 'Navigation bar with logo and links'),
    const WebComponent(
        'Hero Section', LucideIcons.star, 'Full-width hero with CTA'),
    const WebComponent(
        'Pricing Table', LucideIcons.creditCard, '3-tier pricing cards'),
    const WebComponent(
        'FAQ Accordion', LucideIcons.helpCircle, 'Expandable Q&A items'),
    const WebComponent(
        'Contact Form', LucideIcons.mail, 'Name, email, message fields'),
    const WebComponent('Footer', LucideIcons.arrowDown, 'Multi-column footer'),
    const WebComponent('Card Grid', LucideIcons.grid, 'Responsive card layout'),
    const WebComponent(
        'Modal/Dialog', LucideIcons.maximize2, 'Centered overlay modal'),
    const WebComponent('Tabs', LucideIcons.layout, 'Tabbed content switcher'),
    const WebComponent(
        'Testimonials', LucideIcons.quote, 'Customer review carousel'),
    const WebComponent(
        'Stats Bar', LucideIcons.barChart3, 'Animated number counters'),
    const WebComponent('Timeline', LucideIcons.clock, 'Vertical step timeline'),
  ];
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Text('Component Library',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('Tap to insert',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Theme.of(context).hintColor)),
            ]),
          ),
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.3,
              ),
              itemCount: components.length,
              itemBuilder: (_, i) {
                final comp = components[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    askCtrl.text += comp.prompt;
                    onInserted();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.surface : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : Dt.hairline),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(comp.icon, size: 18, color: Dt.accent),
                          const SizedBox(height: 4),
                          Text(comp.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

void shareProjectLink(BuildContext context) async {
  final p = _c.project.value;
  if (p == null) return;
  final ws = Get.find<AgentWorkspaceService>();
  final files = await ws.listFiles(p.id);
  final fileMap = <String, String>{};
  for (final f in files) {
    final content = await ws.readFile(p.id, f);
    if (content != null) fileMap[f] = content;
  }
  if (fileMap.isEmpty) return;
  // Compress to a data URL (base64 of JSON).
  final json =
      jsonEncode({'name': p.name, 'framework': p.framework, 'files': fileMap});
  final encoded = base64UrlEncode(utf8.encode(json));
  final shareUrl = 'https://cubiclm.vercel.app/view?data=$encoded';
  // Copy to clipboard.
  await Clipboard.setData(ClipboardData(text: shareUrl));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share link copied to clipboard!')),
    );
  }
}

void exportToGitHub(BuildContext context) async {
  final p = _c.project.value;
  if (p == null) return;
  final tokenCtrl = TextEditingController();
  final repoCtrl = TextEditingController(
      text: p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-'));
  final ok = await Get.dialog<bool>(AlertDialog(
    title: const Text('Export to GitHub'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: tokenCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'GitHub Personal Access Token',
            isDense: true,
            prefixIcon: Icon(LucideIcons.key, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: repoCtrl,
          decoration: const InputDecoration(
            labelText: 'Repository name',
            isDense: true,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Get.back(result: false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Get.back(result: true),
        child: const Text('Export'),
      ),
    ],
  ));
  if (ok != true || tokenCtrl.text.trim().isEmpty) return;
  try {
    final ws = Get.find<AgentWorkspaceService>();
    final files = await ws.listFiles(p.id);
    final fileMap = <String, String>{};
    for (final f in files) {
      final content = await ws.readFile(p.id, f);
      if (content != null) fileMap[f] = content;
    }
    final token = tokenCtrl.text.trim();
    final repoName = repoCtrl.text.trim();
    // Create repo.
    final createRes = await http.post(
      Uri.parse('https://api.github.com/user/repos'),
      headers: {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github.v3+json',
      },
      body: jsonEncode({'name': repoName, 'auto_init': false}),
    );
    if (createRes.statusCode != 201) {
      throw Exception('GitHub repo creation failed (${createRes.statusCode})');
    }
    // Upload each file.
    for (final e in fileMap.entries) {
      await http.put(
        Uri.parse('https://api.github.com/repos/$repoName/contents/${e.key}'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
        body: jsonEncode({
          'message': 'Add ${e.key}',
          'content': base64Encode(utf8.encode(e.value)),
        }),
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to github.com/$repoName')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub export failed: $e')),
      );
    }
  }
}

/// Short label for the builder composer model pill (mirrors chat).
String builderModelLabel() {
  final s = Get.find<SettingsController>();
  if (s.inferenceMode.value == 'cloud') {
    final m = s.selectedCloudModelName;
    if (m.isEmpty) return 'Cloud';
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
  if (name.isEmpty) return 'Local';
  final stripped = name.replaceAll(
      RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
  return stripped.length > 14 ? '${stripped.substring(0, 14)}…' : stripped;
}

Future<void> _pickScreenshot() async {
  final picker = ImagePicker();
  final x =
      await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (x != null) {
    final bytes = await x.readAsBytes();
    _c.attachedImage.value = base64Encode(bytes);
  }
}

/// "+" sheet: every builder tool in one place (left-side entry point).
void showBuilderToolsSheet(BuildContext context, bool isDark, bool hasProject,
    {required TextEditingController askCtrl,
    required VoidCallback onInserted}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 8, top: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceLight : Dt.hairline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            Text('Builder tools',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('All options here',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ]),
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            if (!hasProject)
              ListTile(
                leading: const Icon(LucideIcons.layers, size: 22),
                title: Text('Framework — ${frameworkShort(_c.framework.value)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showFrameworkSheet(context);
                },
              ),
            if (!hasProject)
              Obx(() => SwitchListTile(
                    secondary: const Icon(LucideIcons.map, size: 22),
                    title: Text('Plan mode',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    value: _c.planMode.value,
                    onChanged: (v) => _c.planMode.value = v,
                  )),
            Obx(() => SwitchListTile(
                  secondary: const Icon(LucideIcons.brain, size: 22),
                  title: Text('Extended thinking',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  value: _c.extendedThinking.value,
                  onChanged: (v) => _c.extendedThinking.value = v,
                )),
            Obx(() => SwitchListTile(
                  secondary: const Icon(LucideIcons.globe, size: 22),
                  title: Text('Web search',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  value: _c.webSearch.value,
                  onChanged: (v) => _c.webSearch.value = v,
                )),
            ListTile(
              leading: const Icon(LucideIcons.puzzle, size: 22),
              title: Text('Component library',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showComponentLibrary(context, isDark,
                    askCtrl: askCtrl, onInserted: onInserted);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.image, size: 22),
              title: Text('Attach screenshot',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickScreenshot();
              },
            ),
            if (hasProject)
              ListTile(
                leading: const Icon(LucideIcons.shieldCheck, size: 22),
                title: Text('Auto-test project',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _c.runAutoTest();
                },
              ),
            ListTile(
              leading: const Icon(LucideIcons.box, size: 22),
              title: Text('Switch model',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text(builderModelLabel(),
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showModelSwitcherSheet(context);
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
      ]),
    ),
  );
}

void showRenameDialog(BuildContext context, bool isDark, String path,
    {String? openFile, required ValueSetter<String?> onPickFile}) {
  final pathCtrl = TextEditingController(text: path);
  showDialog(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rename file',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: pathCtrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'New path', isDense: true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final ws = Get.find<AgentWorkspaceService>();
            await ws.renameFile(_c.project.value!.id, path, pathCtrl.text);
            if (openFile == path) {
              onPickFile(null);
            }
            await _c.notifyFilesChanged();
            if (dlgCtx.mounted) Navigator.pop(dlgCtx);
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

Future<void> showSearchResults(BuildContext context, bool isDark, String query,
    {required ValueSetter<String?> onPickFile}) async {
  if (query.trim().isEmpty || _c.project.value == null) return;
  final ws = Get.find<AgentWorkspaceService>();
  final hits = await ws.searchCode(_c.project.value!.id, query);
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        shrinkWrap: true,
        children: [
          Text('“$query” — ${hits.length} file(s)',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (hits.isEmpty)
            Text('No matches.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: Theme.of(context).hintColor)),
          for (final e in hits.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.key,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('lines ${e.value.join(', ')}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                onPickFile(e.key);
              },
            ),
        ],
      ),
    ),
  );
}

void showAddDialog(BuildContext context, bool isDark,
    {required ValueSetter<String?> onPickFile}) {
  final pathCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Add file',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: pathCtrl,
        autofocus: true,
        decoration: const InputDecoration(
            labelText: 'Path (e.g. about.html)', isDense: true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final ws = Get.find<AgentWorkspaceService>();
            final pid = _c.project.value?.id;
            if (pid == null) {
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              return;
            }
            final err = await ws.writeFile(pid, pathCtrl.text, '');
            if (dlgCtx.mounted) Navigator.pop(dlgCtx);
            if (err != null) {
              Get.snackbar('Add failed', err,
                  snackPosition: SnackPosition.BOTTOM);
            } else {
              await _c.notifyFilesChanged();
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void showFrameworkSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Framework',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          Obx(() => RadioGroup<String>(
                groupValue: _c.framework.value,
                onChanged: (v) {
                  if (v != null) _c.framework.value = v;
                  Navigator.pop(context);
                },
                child: Column(
                  children: [
                    for (final f in webFrameworks)
                      RadioListTile<String>(
                        dense: true,
                        title: Text(f,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                        value: f,
                        activeColor: Dt.accent,
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

void showLibrarySheet(BuildContext context) {
  final libraries = ['Auto', 'shadcn/ui', 'Tailwind CSS', 'Lucide Icons', 'Material UI'];
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Component Library',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          Obx(() => Column(
                children: [
                  for (final lib in libraries)
                    RadioListTile<String>(
                      dense: true,
                      title: Text(lib,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      value: lib,
                      groupValue: _c.selectedLibrary.value,
                      onChanged: (v) {
                        if (v != null) _c.selectedLibrary.value = v;
                        Navigator.pop(context);
                      },
                      activeColor: Dt.accent,
                    ),
                ],
              )),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

void showDesignSystemSheet(BuildContext context) {
  final systems = ['Modern', 'Retro', 'Enterprise', 'Minimalist', 'Playful'];
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Design System',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          Obx(() => Column(
                children: [
                  for (final ds in systems)
                    RadioListTile<String>(
                      dense: true,
                      title: Text(ds,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      value: ds,
                      groupValue: _c.selectedDesignSystem.value,
                      onChanged: (v) {
                        if (v != null) _c.selectedDesignSystem.value = v;
                        Navigator.pop(context);
                      },
                      activeColor: Dt.accent,
                    ),
                ],
              )),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

void showBuilderSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Builder Settings',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Obx(() => SwitchListTile(
                  title: const Text('Live Preview Update'),
                  subtitle: const Text('Reload preview as AI writes'),
                  value: _c.enableLivePreview.value,
                  onChanged: (v) => _c.enableLivePreview.value = v,
                )),
            Obx(() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Live Update Throttle: ${_c.liveFlushThrottle.value}ms',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Slider(
                      value: _c.liveFlushThrottle.value.toDouble(),
                      min: 150,
                      max: 5000,
                      divisions: 20,
                      onChanged: _c.enableLivePreview.value
                          ? (v) => _c.liveFlushThrottle.value = v.toInt()
                          : null,
                    ),
                  ],
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}
