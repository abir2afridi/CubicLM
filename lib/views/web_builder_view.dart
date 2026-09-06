import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/web_builder_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/web_project.dart';

/// CubicWeb Build (Toolkit): prompt → complete website in any framework.
/// Code explorer + live browser preview + one-tap ZIP export.
class WebBuilderView extends StatefulWidget {
  const WebBuilderView({super.key});

  @override
  State<WebBuilderView> createState() => _WebBuilderViewState();
}

class _WebBuilderViewState extends State<WebBuilderView> {
  late final WebBuilderController c;
  final _promptCtrl = TextEditingController();
  int _fileIdx = 0;
  String _pane = 'code'; // code | preview
  int _reloadNonce = 0;

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<WebBuilderController>()
        ? Get.find<WebBuilderController>()
        : Get.put(WebBuilderController());
    _promptCtrl.text = c.topic.value;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  int get _safeIdx =>
      c.files.isEmpty ? 0 : _fileIdx.clamp(0, c.files.length - 1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('CubicWeb Build',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        actions: [
          Obx(() => c.hasProject
              ? IconButton(
                  tooltip: 'Export ZIP',
                  icon: Icon(LucideIcons.packageOpen,
                      color: isDark
                          ? AppColors.textPrimary
                          : Dt.iconDefault),
                  onPressed: c.exportZip,
                )
              : const SizedBox.shrink()),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _composerCard(context, isDark),
            if (c.lastError.value != null) ...[
              const SizedBox(height: 10),
              _errorBox(context),
            ],
            if (c.hasProject) ...[
              const SizedBox(height: 12),
              _paneSwitch(),
              const SizedBox(height: 10),
              if (_pane == 'code') _codePane(context, isDark),
              if (_pane == 'preview')
                _previewPane(context, isDark, c.revision.value),
            ] else if (c.generating.value) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Center(
                child: Text('Building your website…',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Theme.of(context).hintColor)),
              ),
            ] else ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Describe the site — pages, style, features.\n'
                  'The AI writes every file; you preview + export ZIP.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.5,
                      color: Theme.of(context).hintColor),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  // ── Composer ──

  Widget _composerCard(BuildContext context, bool isDark) {
    return _card(isDark, [
      TextField(
        controller: _promptCtrl,
        enabled: !c.generating.value,
        maxLines: 4,
        minLines: 2,
        onChanged: (v) => c.topic.value = v,
        style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
        decoration: InputDecoration(
          hintText: 'e.g. Portfolio site for a photographer, dark theme, gallery + contact',
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
        onChanged: c.generating.value
            ? null
            : (v) {
                if (v != null) c.framework.value = v;
              },
        decoration: InputDecoration(
          labelText: 'Framework',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
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
                  _fileIdx = 0;
                  await c.generate();
                },
          icon: const Icon(LucideIcons.globe, size: 18),
          label: Text(c.hasProject ? 'Rebuild site' : 'Build website'),
          style: FilledButton.styleFrom(
            backgroundColor: Dt.accent,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _errorBox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(c.lastError.value!,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5, color: AppColors.error, height: 1.4)),
    );
  }

  Widget _paneSwitch() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'code',
            icon: Icon(LucideIcons.code, size: 15),
            label: Text('Code'),
          ),
          ButtonSegment(
            value: 'preview',
            icon: Icon(LucideIcons.eye, size: 15),
            label: Text('Preview'),
          ),
        ],
        selected: {_pane},
        onSelectionChanged: (s) => setState(() => _pane = s.first),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // ── Code pane ──

  Widget _codePane(BuildContext context, bool isDark) {
    final idx = _safeIdx;
    final file = c.files[idx];
    final busy = c.generating.value && c.regenIndex.value == idx;
    return _card(isDark, [
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < c.files.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(c.files[i].path,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                  selected: i == idx,
                  selectedColor: Dt.accent.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _fileIdx = i),
                ),
              ),
            IconButton(
              tooltip: 'Add file',
              icon: const Icon(LucideIcons.plus, size: 18),
              onPressed: () => _showAddDialog(context, isDark),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Text(
            '${file.content.length} chars',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: Theme.of(context).hintColor),
          ),
        ),
        if (busy)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...[
          _iconBtn(context, LucideIcons.refreshCw, 'Regenerate this file',
              () => c.regenerateFile(idx)),
          _iconBtn(context, LucideIcons.pencil, 'Edit file',
              () => _showEditDialog(context, isDark, idx, file)),
          _iconBtn(context, LucideIcons.copy, 'Copy file', () {
            Clipboard.setData(ClipboardData(text: file.content));
          }),
          _iconBtn(context, LucideIcons.trash2, 'Delete file',
              () {
                c.deleteFile(idx);
                setState(() => _fileIdx = 0);
              },
              color: AppColors.error.withValues(alpha: 0.8)),
        ],
      ]),
      const SizedBox(height: 8),
      Container(
        constraints: const BoxConstraints(maxHeight: 380),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: SelectableText(
              file.content.isEmpty ? '(empty file)' : file.content,
              style: GoogleFonts.firaCode(
                fontSize: 12,
                height: 1.55,
                color: isDark
                    ? const Color(0xFFCDD6F4)
                    : Dt.textPrimary,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _iconBtn(BuildContext context, IconData icon, String tip,
      VoidCallback? onTap,
      {Color? color}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon,
              size: 16,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : (color ?? Theme.of(context).hintColor)),
        ),
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, bool isDark, int idx, WebFile file) {
    final pathCtrl = TextEditingController(text: file.path);
    final bodyCtrl = TextEditingController(text: file.content);
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit file',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(
                  labelText: 'Path', isDense: true),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 320,
              child: TextField(
                controller: bodyCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.firaCode(fontSize: 12, height: 1.5),
                decoration: const InputDecoration(
                  labelText: 'Content',
                  alignLabelWithHint: true,
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              c.applyEdit(idx, pathCtrl.text, bodyCtrl.text);
              Navigator.pop(dlgCtx);
            },
            child: const Text('Save'),
          ),
        ],
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
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: pathCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Path (e.g. about.html)',
              hintText: 'No .. or absolute paths',
              isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              c.addFile(pathCtrl.text);
              setState(() => _fileIdx = c.files.length - 1);
              Navigator.pop(dlgCtx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ── Preview pane ──

  Widget _previewPane(BuildContext context, bool isDark, int revision) {
    if (!c.previewSupported) {
      return _card(isDark, [
        Row(children: [
          const Icon(LucideIcons.info, size: 18, color: Dt.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${c.framework.value} needs a build step (npm install && npm run dev) — open the ZIP in VS Code. Live preview runs Single HTML and HTML+CSS+JS projects.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, height: 1.5),
            ),
          ),
        ]),
      ]);
    }
    return _card(isDark, [
      Row(children: [
        Expanded(
          child: Text('Live preview',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          tooltip: 'Reload preview',
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          onPressed: () => setState(() => _reloadNonce++),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 480,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<String?>(
            key: ValueKey('preview-$revision-$_reloadNonce'),
            future: c.preparePreview(),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator());
              }
              final path = snap.data;
              if (path == null || path.isEmpty) {
                return Center(
                  child: Text('Nothing browser-runnable here.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Theme.of(context).hintColor)),
                );
              }
              return _PreviewWebView(key: ValueKey(path), filePath: path);
            },
          ),
        ),
      ),
    ]);
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

/// Isolated WebView so reloads don't rebuild the whole page.
class _PreviewWebView extends StatefulWidget {
  final String filePath;
  const _PreviewWebView({super.key, required this.filePath});

  @override
  State<_PreviewWebView> createState() => _PreviewWebViewState();
}

class _PreviewWebViewState extends State<_PreviewWebView> {
  bool _loading = true;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      InAppWebView(
        initialFile: widget.filePath,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // Same origin fix as code preview: file:// alone denies
          // DOM storage; enabled here so site saves/scores keep working.
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
              color: (isDark ? Colors.black : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppColors.error)),
          ),
        ),
    ]);
  }
}
