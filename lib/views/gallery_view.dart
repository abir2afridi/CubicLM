import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../core/colors.dart';
import '../services/hive_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/image_viewer.dart';

class GalleryController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final items = <Map<dynamic, dynamic>>[].obs;

  /// Paths known to exist — computed once per refresh, not per tile build
  /// (a stat() per build × N tiles × rebuilds was pure UI-thread waste).
  final existingPaths = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refreshGallery();
  }

  void refreshGallery() {
    items.value = _hive.getAllImageHistory();
    final seen = <String>{};
    for (final e in items) {
      final p = e['path']?.toString() ?? '';
      if (p.isEmpty) continue;
      try {
        if (File(p).existsSync()) seen.add(p);
      } catch (_) {}
    }
    existingPaths.assignAll(seen);
  }

  Future<void> deleteItem(String id) async {
    await _hive.deleteImageHistory(id);
    refreshGallery();
  }

  Future<void> clearAll() async {
    await _hive.clearImageHistory();
    refreshGallery();
  }
}

class GalleryView extends StatefulWidget {
  const GalleryView({super.key});

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  late final GalleryController _ctrl;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<GalleryController>()) {
      _ctrl = Get.find<GalleryController>();
      _ctrl.refreshGallery();
    } else {
      _ctrl = Get.put(GalleryController());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final items = _ctrl.items;
      if (items.isEmpty) {
        return _buildEmpty(context, isDark);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isDark, items.length),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final e = items[index];
              final path = e['path']?.toString() ?? '';
              return _GalleryTile(
                entry: e,
                isDark: isDark,
                exists: path.isNotEmpty &&
                    _ctrl.existingPaths.contains(path),
                onRefresh: _ctrl.refreshGallery,
                onDelete: () => _ctrl.deleteItem(e['id'].toString()),
              );
            },
          ),
        ],
      );
    });
  }

  Widget _buildHeader(BuildContext context, bool isDark, int count) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Dt.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(LucideIcons.image, size: 18, color: Dt.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generated Images',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              Text(
                '$count image${count == 1 ? '' : 's'} saved locally',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Obx(() {
          final hasItems = _ctrl.items.isNotEmpty;
          if (!hasItems) return const SizedBox.shrink();
          return IconButton(
            tooltip: 'Clear all',
            onPressed: () => _confirmClearAll(context),
            icon: Icon(LucideIcons.trash2,
                size: 18, color: AppColors.error.withValues(alpha: 0.7)),
            style: IconButton.styleFrom(
              backgroundColor:
                  AppColors.error.withValues(alpha: isDark ? 0.08 : 0.06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _ctrl.refreshGallery,
          icon: Icon(LucideIcons.refreshCw,
              size: 18,
              color: isDark ? AppColors.textSecondary : Dt.textSecondary),
          style: IconButton.styleFrom(
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.image,
                size: 28, color: Dt.accent),
          ),
          const SizedBox(height: 14),
          Text(
            'No generated images yet',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Images you generate with Stable Diffusion will appear here.\nUse /image, “generate image” or the image model in chat.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Dt.pillMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.lightbulb,
                    size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Tip: Load an SD model from Local → Image filter',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? Dt.cardDark : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Clear gallery?',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Text(
              'Delete all generated images? Files will be removed from device storage. This cannot be undone.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common_cancel'.tr),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('common_delete'.tr),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await _ctrl.clearAll();
      if (context.mounted) {
        Get.snackbar('Gallery cleared', 'All images removed',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }
}

class _GalleryTile extends StatelessWidget {
  final Map<dynamic, dynamic> entry;
  final bool isDark;
  final bool exists;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _GalleryTile({
    required this.entry,
    required this.isDark,
    required this.exists,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final path = entry['path']?.toString() ?? '';
    final prompt = entry['prompt']?.toString() ?? '';
    final size = entry['size']?.toString() ?? '';
    final tsMs = (entry['timestampMs'] as num?)?.toInt();
    final date = tsMs != null
        ? DateTime.fromMillisecondsSinceEpoch(tsMs)
        : DateTime.tryParse(entry['timestamp']?.toString() ?? '');

    // Existence comes from the controller (computed once per refresh).
    final file = (path.isNotEmpty && exists) ? File(path) : null;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openViewer(context, file, path),
      onLongPress: () => _showActions(context, file, path, prompt),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (file != null)
                    Image.file(
                      file,
                      fit: BoxFit.cover,
                      // Grid tile only — viewer opens the full file.
                      cacheWidth: 512,
                      errorBuilder: (_, __, ___) => _broken(context),
                      gaplessPlayback: true,
                    )
                  else
                    _broken(context),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        size.isEmpty ? 'image' : size,
                        style: GoogleFonts.firaCode(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (prompt.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Text(
                          prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.02),
              child: Row(
                children: [
                  Icon(LucideIcons.clock3,
                      size: 10,
                      color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      date == null ? '—' : _fmtDate(date),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(LucideIcons.moreHorizontal,
                      size: 12,
                      color: Theme.of(context)
                          .hintColor
                          .withValues(alpha: 0.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _broken(BuildContext context) {
    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.imageOff,
                size: 26,
                color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 6),
            Text(
              'Missing file',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openViewer(
      BuildContext context, File? file, String path) async {
    if (file == null || !file.existsSync()) {
      Get.snackbar('File missing', 'Image file no longer exists',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await ImageViewer.showBytes(context, bytes);
    } catch (e) {
      Get.snackbar('Open failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _showActions(
      BuildContext context, File? file, String path, String prompt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? Dt.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16, top: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceLight : Dt.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (prompt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Dt.pillMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      prompt,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Dt.textPrimary,
                      ),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(LucideIcons.eye, size: 22, color: Dt.accent),
                title: Text('View fullscreen',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openViewer(context, file, path);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.share2, size: 22),
                title: Text('Share image',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareImage(file, path, prompt);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.trash2,
                    size: 22, color: AppColors.error),
                title: Text('Delete',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareImage(File? file, String path, String prompt) async {
    if (file == null || !file.existsSync()) {
      Get.snackbar('Share failed', 'File not found',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(path)],
        text: prompt.isEmpty ? 'Generated with CubicLM' : prompt,
      );
    } catch (e) {
      Get.snackbar('Share failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? Dt.cardDark : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Delete image?',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Text(
              'Remove this image from gallery and delete the file?',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common_cancel'.tr),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('common_delete'.tr),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      onDelete();
      Get.snackbar('Deleted', 'Image removed from gallery',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
