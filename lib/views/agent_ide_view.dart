import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/agent_workspace.dart';
import '../theme/design_tokens.dart';
import '../utils/web_project.dart';

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
  String _tab = 'preview'; // preview | files
  String? _openFile;

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<AgentController>()
        ? Get.find<AgentController>()
        : Get.put(AgentController());
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _askCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(
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
        ),
        actions: [
          Obx(() => c.project.value == null
              ? const SizedBox.shrink()
              : PopupMenuButton<String>(
                  tooltip: 'Project',
                  icon: Icon(LucideIcons.folderGit2,
                      color: isDark
                          ? AppColors.textPrimary
                          : Dt.iconDefault),
                  onSelected: (v) => _onProjectMenu(v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'switch',
                      child: Text('Switch project (${c.projectsOf().length})',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14)),
                    ),
                    const PopupMenuItem(
                      value: 'new',
                      child: Text('New project',
                          style: TextStyle(fontSize: 14)),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('Export ZIP',
                          style: TextStyle(fontSize: 14)),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename project',
                          style: TextStyle(fontSize: 14)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete project',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, color: AppColors.error)),
                    ),
                  ],
                )),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        if (c.project.value == null) return _newProjectCard(context, isDark);
        return Column(children: [
          _projectHeader(context, isDark),
          _tabSwitch(),
          Expanded(
            child: _tab == 'preview'
                ? _previewPane(context, isDark, c.revision.value)
                : _filesPane(context, isDark),
          ),
          _askBar(context, isDark),
        ]);
      }),
    );
  }

  // ── New project ──

  Widget _newProjectCard(BuildContext context, bool isDark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _card(isDark, [
          Text('What should the AI build?',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl,
            maxLines: 4,
            minLines: 2,
            onChanged: (v) => c.topic.value = v,
            style:
                GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'e.g. Modern e-commerce site with cart — React + Tailwind',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: c.framework.value,
            items: [
              for (final f in webFrameworks)
                DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) {
              if (v != null) c.framework.value = v;
            },
            decoration: InputDecoration(
              labelText: 'Framework',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Static + ESM frameworks preview on-device. Builds needing Node/SSR go cloud (Phase 2).',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: c.generating.value ||
                      _promptCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      c.topic.value = _promptCtrl.text;
                      await c.newProject();
                    },
              icon: const Icon(LucideIcons.hammer, size: 18),
              label: const Text('Build project'),
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
        if (c.generating.value) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (c.lastError.value != null) ...[
          const SizedBox(height: 10),
          Text(c.lastError.value!,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: AppColors.error, height: 1.4)),
        ],
      ],
    );
  }

  // ── Header / tabs / ask ──

  Widget _projectHeader(BuildContext context, bool isDark) {
    final p = c.project.value!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                    '${p.framework} · ${c.files.length} files',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Theme.of(context).hintColor)),
              ]),
        ),
        if (c.generating.value || c.fixing.value)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(
            top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Dt.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.consoleError.value != null &&
              c.consoleError.value!.isNotEmpty)
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
                  onPressed:
                      c.fixing.value ? null : () => c.repairFromError(),
                  child: Text(c.fixing.value ? 'Fixing…' : 'Fix'),
                ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _askCtrl,
                minLines: 1,
                maxLines: 3,
                onChanged: (v) => c.topic.value = v,
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask AI to change anything…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(() => IconButton.filled(
                  tooltip: 'Apply change',
                  icon: c.generating.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.send,
                          size: 18),
                  style: IconButton.styleFrom(
                      backgroundColor: Dt.accent),
                  onPressed: c.generating.value ||
                          _askCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          c.topic.value = _askCtrl.text;
                          _askCtrl.clear();
                          await c.modifyProject();
                        },
                )),
          ]),
        ]),
      ),
    );
  }

  // ── Preview pane ──

  Widget _previewPane(BuildContext context, bool isDark, int revision) {
    final url = c.previewUrl.value;
    if (url == null || url.isEmpty) {
      return Center(
        child: Text('Preview unavailable.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Theme.of(context).hintColor)),
      );
    }
    return _AgentPreview(
      key: ValueKey('agent-$revision-$url'),
      url: url,
      onConsoleError: (msg) => c.onConsoleError(msg),
    );
  }

  // ── Files pane ──

  Widget _filesPane(BuildContext context, bool isDark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text('${c.files.length} files',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).hintColor)),
          ),
          TextButton.icon(
            onPressed: () => _showAddDialog(context, isDark),
            icon: const Icon(LucideIcons.plus, size: 15),
            label: const Text('Add'),
          ),
        ]),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search in code…',
            isDense: true,
            prefixIcon:
                const Icon(LucideIcons.search, size: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
          ),
          onSubmitted: (q) => _showSearchResults(context, isDark, q),
        ),
        const SizedBox(height: 8),
        for (final path in c.files)
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(_iconFor(path),
                  size: 18, color: Dt.accent),
              title: Text(path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Open',
                  icon: const Icon(LucideIcons.chevronRight, size: 18),
                  onPressed: () =>
                      setState(() => _openFile = path),
                ),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(LucideIcons.pencil, size: 15),
                  onPressed: () =>
                      _showRenameDialog(context, isDark, path),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(LucideIcons.trash2,
                      size: 16,
                      color: AppColors.error.withValues(alpha: 0.8)),
                  onPressed: () async {
                    final ws = Get.find<AgentWorkspaceService>();
                    await ws.deleteFile(
                        c.project.value!.id, path);
                    if (_openFile == path) {
                      setState(() => _openFile = null);
                    }
                    await c.notifyFilesChanged();
                  },
                ),
              ]),
              onTap: () => setState(() => _openFile =
                  _openFile == path ? null : path),
            ),
          ),
        if (_openFile != null &&
            c.files.contains(_openFile)) ...[
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
    if (p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.svg')) {
      return LucideIcons.image;
    }
    return LucideIcons.file;
  }

  Widget _fileEditor(BuildContext context, bool isDark, String path) {
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
                    child:
                        CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return _FileEditorCard(
          key: ValueKey('card-$path'),
          path: path,
          initial: snap.data ?? '',
          isDark: isDark,
        );
      },
    );
  }

  void _onProjectMenu(String v) async {
    if (v == 'new') {
      c.project.value = null;
      c.files.clear();
      c.previewUrl.value = null;
      _promptCtrl.clear();
    } else if (v == 'export') {
      await c.exportZip();
    } else if (v == 'rename') {
      final p = c.project.value;
      if (p == null) return;
      final nameCtrl = TextEditingController(text: p.name);
      final next = await Get.dialog<String>(AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration:
              const InputDecoration(labelText: 'Name', isDense: true),
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
        await c.renameProject(next);
      }
    } else if (v == 'delete') {
      final p = c.project.value;
      if (p == null) return;
      final ok = await Get.dialog<bool>(AlertDialog(
        title: const Text('Delete project?'),
        content: Text('"${p.name}" and all its files will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ));
      if (ok == true) {
        await c.deleteProject(p.id);
        _promptCtrl.clear();
      }
    } else if (v == 'switch') {
      _showProjectSwitcher(context);
    }
  }

  void _showProjectSwitcher(BuildContext context) {
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
                    leading: const Icon(LucideIcons.folderGit2,
                        size: 20),
                    title: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(p.framework,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color:
                                Theme.of(context).hintColor)),
                    trailing:
                        c.project.value?.id == p.id
                            ? const Icon(LucideIcons.check,
                                size: 18, color: Dt.accent)
                            : null,
                    onTap: () {
                      Navigator.pop(context);
                      c.openProject(p);
                    },
                  ),
                if (ws.projects.isEmpty)
                  const ListTile(
                      title: Text('No projects yet.')),
              ],
            ),
          )),
    );
  }

  void _showRenameDialog(
      BuildContext context, bool isDark, String path) {
    final pathCtrl = TextEditingController(text: path);
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename file',
            style:
                GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: pathCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'New path', isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final ws = Get.find<AgentWorkspaceService>();
              await ws.renameFile(
                  c.project.value!.id, path, pathCtrl.text);
              if (_openFile == path) {
                setState(() => _openFile = null);
              }
              await c.notifyFilesChanged();
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSearchResults(
      BuildContext context, bool isDark, String query) async {
    if (query.trim().isEmpty || c.project.value == null) return;
    final ws = Get.find<AgentWorkspaceService>();
    final hits = await ws.searchCode(c.project.value!.id, query);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
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
                      fontSize: 13,
                      color: Theme.of(context).hintColor)),
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
                  setState(() => _openFile = e.key);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, bool isDark) {
    final pathCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add file',
            style:
                GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
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
              final pid = c.project.value?.id;
              if (pid == null) {
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                return;
              }
              final err =
                  await ws.writeFile(pid, pathCtrl.text, '');
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              if (err != null) {
                Get.snackbar('Add failed', err,
                    snackPosition: SnackPosition.BOTTOM);
              } else {
                await c.notifyFilesChanged();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Dt.hairline),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }
}

extension on AgentController {
  List<AgentProject> projectsOf() =>
      Get.find<AgentWorkspaceService>().projects.toList();
}

/// File editor card: owns its controller so parent rebuilds never wipe
/// in-progress edits. Save writes through the workspace service.
class _FileEditorCard extends StatefulWidget {
  final String path;
  final String initial;
  final bool isDark;
  const _FileEditorCard({
    super.key,
    required this.path,
    required this.initial,
    required this.isDark,
  });

  @override
  State<_FileEditorCard> createState() => _FileEditorCardState();
}

class _FileEditorCardState extends State<_FileEditorCard> {
  late final TextEditingController _ctrl;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _ctrl.addListener(() {
      final d = _ctrl.text != widget.initial;
      if (d != _dirty && mounted) setState(() => _dirty = d);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          if (_dirty)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Dt.accent, shape: BoxShape.circle),
            ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(LucideIcons.copy, size: 16),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _ctrl.text)),
          ),
          IconButton(
            tooltip: 'Save edits',
            icon: const Icon(LucideIcons.check, size: 18),
            color: Dt.accent,
            onPressed: () async {
              final ws = Get.find<AgentWorkspaceService>();
              final ac = Get.find<AgentController>();
              final pid = ac.project.value?.id;
              if (pid == null) return;
              final err =
                  await ws.writeFile(pid, widget.path, _ctrl.text);
              if (err != null && context.mounted) {
                Get.snackbar('Save failed', err,
                    snackPosition: SnackPosition.BOTTOM);
              } else {
                await ac.notifyFilesChanged();
                if (context.mounted) {
                  Get.snackbar('Saved', widget.path,
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 1));
                }
              }
            },
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF1E1E2E)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
              decoration:
                  const InputDecoration.collapsed(hintText: ''),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Preview WebView with console-error forwarding to the agent loop.
class _AgentPreview extends StatefulWidget {
  final String url;
  final void Function(String) onConsoleError;
  const _AgentPreview(
      {super.key, required this.url, required this.onConsoleError});

  @override
  State<_AgentPreview> createState() => _AgentPreviewState();
}

class _AgentPreviewState extends State<_AgentPreview> {
  bool _loading = true;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 460,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: true,
              transparentBackground: false,
            ),
            onLoadStop: (_, __) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = null;
                });
              }
            },
            onReceivedError: (_, __, err) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = err.description;
                });
              }
            },
            onConsoleMessage: (_, msg) {
              final text = msg.message;
              if (msg.messageLevel == ConsoleMessageLevel.ERROR &&
                  text.isNotEmpty &&
                  mounted) {
                setState(() => _error = text);
                widget.onConsoleError(text);
              }
            },
          ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null && !_loading)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .cardColor
                      .withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.error)),
              ),
            ),
        ]),
      ),
    );
  }
}
