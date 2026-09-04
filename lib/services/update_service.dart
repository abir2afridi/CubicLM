import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/constants/platform_links.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import 'app_log_service.dart';
import 'hive_service.dart';

/// Minimal auto-update checker — polls GitHub Releases API once per 24h.
///
/// - On app start (after 3s delay) does GET
///   https://api.github.com/repos/abir2afridi/CubicLM/releases/latest,
///   compares tag_name vs package_info_plus version.
/// - Caches last check timestamp in Hive (settings box) under
///   [_kLastCheckMs].
/// - If a newer version is available, shows a top snackbar with
///   "What's New" / "Download" actions opening [PlatformLinks.changelogUrl]
///   and [PlatformLinks.desktopDownloadUrl] via url_launcher.
/// - Manual checks bypass the 24h cooldown and show explicit feedback.
/// - Handles offline / errors gracefully; never throws to callers.
class UpdateService extends GetxService {
  static const String _endpoint =
      'https://api.github.com/repos/abir2afridi/CubicLM/releases/latest';
  static const String _kLastCheckMs = 'update_last_check_ms';
  static const String _kLastKnownVersion = 'update_last_known_version';
  static const Duration _cooldown = Duration(hours: 24);
  static const Duration _initialDelay = Duration(seconds: 3);
  static const Duration _httpTimeout = Duration(seconds: 8);

  bool _checking = false;

  /// The latest version string seen from GitHub (e.g. "1.2.0").
  final lastKnownVersion = ''.obs;

  /// Whether an update newer than the installed version is available.
  final updateAvailable = false.obs;

  /// Download progress (0.0 – 1.0) while an in-app update is downloading.
  final downloadProgress = 0.0.obs;

  /// Whether an APK download is currently in progress.
  final isDownloading = false.obs;

  /// The APK download URL extracted from the latest release assets.
  String? _apkDownloadUrl;

  /// The chosen APK filename (ABI-matched) for display during download.
  String _apkFileName = '';

  /// The latest release tag for display during download.
  String _latestTag = '';

  Future<UpdateService> init() async {
    // Restore persisted state from Hive.
    final cached = _getLastKnownVersion();
    if (cached != null && cached.isNotEmpty) {
      lastKnownVersion.value = cached;
    }
    return this;
  }

  /// Auto check — respects 24h cooldown and starts after 3s delay.
  /// Use [force]=true to bypass cooldown and delay (manual check).
  /// When [silent] is true (default for auto), no "up to date" or
  /// offline snackbars are shown; only an available-update snackbar.
  Future<void> check({bool force = false, bool silent = true}) async {
    if (_checking) return;
    _checking = true;
    try {
      if (!force) {
        await Future.delayed(_initialDelay);
        // Re-check _checking after delay in case disposed.
        final lastMs = _getLastCheckMs();
        if (lastMs != null) {
          final elapsed = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
          if (elapsed < _cooldown) return;
        }
      }

      final current = await _getCurrentVersion();
      if (current == null || current.isEmpty) return;

      final release = await _fetchLatestRelease();
      if (release == null) {
        if (!silent) {
          AppSnackbar.showTop(
            'Could not check for updates',
            'You appear to be offline. Try again later.',
            icon: LucideIcons.wifiOff,
            type: 'general',
            iconName: 'wifi_off',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      final rawTag = (release['tag_name'] as String?)?.trim() ?? '';
      if (rawTag.isEmpty) {
        if (!silent) {
          AppSnackbar.showTop(
            'No releases found',
            'Please try again later.',
            icon: LucideIcons.info,
            type: 'general',
            iconName: 'info',
            duration: const Duration(seconds: 2),
          );
        }
        return;
      }

      // Persist last check timestamp regardless of result (throttle).
      await _setLastCheckMs(DateTime.now().millisecondsSinceEpoch);

      final latest = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
      final cmp = _compareVersions(latest, current);
      if (cmp > 0) {
        lastKnownVersion.value = latest;
        updateAvailable.value = true;
        _latestTag = rawTag;
        _apkDownloadUrl = await _extractApkUrl(release);
        await _setLastKnownVersion(latest);
        _showUpdateSnackbar(rawTag);
      } else {
        lastKnownVersion.value = latest;
        updateAvailable.value = false;
        _apkDownloadUrl = null;
        await _setLastKnownVersion(latest);
        if (!silent) {
          AppSnackbar.showTop(
            "You're up to date",
            'v$current is the latest version.',
            icon: LucideIcons.checkCircle2,
            type: 'general',
            iconName: 'check_circle_2',
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e, s) {
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().warning(
            'Update check failed',
            details: '$e\n$s',
            category: LogCategory.system,
          );
        }
      } catch (_) {}
      if (!silent) {
        AppSnackbar.showTop(
          'Could not check for updates',
          'You appear to be offline.',
          icon: LucideIcons.wifiOff,
          type: 'general',
          iconName: 'wifi_off',
          duration: const Duration(seconds: 2),
        );
      }
    } finally {
      _checking = false;
    }
  }

  /// Backwards-compatible alias for the spec's "manually triggers check".
  Future<void> checkForUpdatesManual() => check(force: true, silent: false);

  /// Downloads the APK from GitHub releases and triggers Android install.
  /// Shows a progress dialog during download, then opens the APK installer.
  Future<void> downloadAndInstallAPK() async {
    if (isDownloading.value) return;
    final url = _apkDownloadUrl;
    if (url == null || url.isEmpty) {
      AppSnackbar.showTop(
        'Download unavailable',
        'Could not find APK download link. Please download from GitHub.',
        icon: LucideIcons.alertTriangle,
        type: 'general',
        iconName: 'alert_triangle',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    isDownloading.value = true;
    downloadProgress.value = 0.0;

    // Show progress dialog.
    Get.dialog(
      Obx(() => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.download, size: 36, color: Dt.accent),
            const SizedBox(height: 16),
            Text(
              'Downloading update...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _apkFileName.isNotEmpty ? _apkFileName : _latestTag,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: downloadProgress.value,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Dt.accent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(downloadProgress.value * 100).toInt()}%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      )),
      barrierDismissible: false,
    );

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/cubiclm_update.apk';

      final dio = Dio();
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            downloadProgress.value = received / total;
          }
        },
        options: Options(
          headers: {'Accept': 'application/octet-stream'},
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      // Close progress dialog.
      if (Get.isDialogOpen == true) Get.back();

      // Android 8+ needs the install-packages grant or the installer
      // silently refuses. Ask first, deep-link to settings on denial.
      if (Platform.isAndroid &&
          !await _ensureInstallPermission(savePath)) {
        return;
      }

      // Trigger APK install.
      final result = await OpenFile.open(savePath);
      if (result.type != ResultType.done) {
        AppSnackbar.showTop(
          'Could not open installer',
          result.message.isNotEmpty ? result.message : 'Please install manually.',
          icon: LucideIcons.alertTriangle,
          type: 'general',
          iconName: 'alert_triangle',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      AppSnackbar.showTop(
        'Download failed',
        '$e',
        icon: LucideIcons.xCircle,
        type: 'general',
        iconName: 'x_circle',
        duration: const Duration(seconds: 3),
      );
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().warning(
            'APK download failed',
            details: '$e',
            category: LogCategory.system,
          );
        }
      } catch (_) {}
    } finally {
      isDownloading.value = false;
      downloadProgress.value = 0.0;
    }
  }

  // ── internals ──

  int? _getLastCheckMs() {
    try {
      if (!Get.isRegistered<HiveService>()) return null;
      return Get.find<HiveService>()
          .getSetting<int>(_kLastCheckMs);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setLastCheckMs(int ms) async {
    try {
      if (!Get.isRegistered<HiveService>()) return;
      await Get.find<HiveService>().setSetting(_kLastCheckMs, ms);
    } catch (_) {}
  }

  String? _getLastKnownVersion() {
    try {
      if (!Get.isRegistered<HiveService>()) return null;
      return Get.find<HiveService>().getSetting<String>(_kLastKnownVersion);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setLastKnownVersion(String version) async {
    try {
      if (!Get.isRegistered<HiveService>()) return;
      await Get.find<HiveService>().setSetting(_kLastKnownVersion, version);
    } catch (_) {}
  }

  Future<String?> _getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 4));
      final v = info.version.trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    try {
      final res = await http
          .get(
            Uri.parse(_endpoint),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(_httpTimeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _showUpdateSnackbar(String tag) {
    // tag includes leading v (e.g., v1.2.0)
    const changelogUrl = PlatformLinks.changelogUrl;

    final bool isAndroid = Platform.isAndroid;
    final bool canInstallInApp = isAndroid && _apkDownloadUrl != null;

    Future<void> openUrl(String url) async {
      try {
        final uri = Uri.parse(url);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().warning(
            'Could not open update link',
            details: url,
            category: LogCategory.system,
          );
        }
      } catch (e) {
        try {
          if (Get.isRegistered<AppLogService>()) {
            Get.find<AppLogService>().warning(
              'Could not open update link',
              details: '$url — $e',
              category: LogCategory.system,
            );
          }
        } catch (_) {}
      }
    }

    AppSnackbar.showTop(
      'Update available: $tag',
      canInstallInApp ? "Tap Update to install in-app" : "What's New  •  Download",
      icon: LucideIcons.download,
      type: 'update_available',
      iconName: 'download',
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () {
          if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
          if (canInstallInApp) {
            downloadAndInstallAPK();
          } else {
            openUrl(PlatformLinks.desktopDownloadUrl);
          }
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          canInstallInApp ? 'Update' : 'Download',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      onTap: () {
        if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
        openUrl(changelogUrl);
      },
    );
  }

  /// Ensures Android allows installs from this app (API 26+). Returns true
  /// when the installer can proceed. On denial, opens system settings and
  /// tells the user where to re-run the update from.
  Future<bool> _ensureInstallPermission(String savePath) async {
    try {
      var status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        status = await Permission.requestInstallPackages.request();
      }
      if (status.isGranted) return true;
      AppSnackbar.showTop(
        'Allow app installs',
        'Enable "Install unknown apps" for CubicLM, then tap Update again.',
        icon: LucideIcons.settings,
        type: 'general',
        iconName: 'settings',
        duration: const Duration(seconds: 5),
        mainButton: TextButton(
          onPressed: () {
            if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
            openAppSettings();
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Open settings',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      );
      return false;
    } catch (_) {
      // Permission plugin unavailable — let the installer try anyway.
      return true;
    }
  }

  /// Extracts the APK download URL from GitHub release assets, matching
  /// this device's ABI. Asset names look like
  /// `cubiclm-v1.3.0-arm64-v8a.apk`. The old first-`.apk`-wins logic would
  /// install an incompatible split (e.g. x86_64 on an arm64 phone).
  Future<String?> _extractApkUrl(Map<String, dynamic> release) async {
    try {
      final assets = release['assets'] as List<dynamic>?;
      if (assets == null || assets.isEmpty) return null;
      final apks = <String, String>{}; // filename -> download url
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        final url = asset['browser_download_url'] as String?;
        if (name.endsWith('.apk') && url != null && url.isNotEmpty) {
          apks[name] = url;
        }
      }
      if (apks.isEmpty) return null;
      if (apks.length == 1) {
        _apkFileName = apks.keys.first;
        return apks.values.first;
      }

      for (final abi in await _deviceAbis()) {
        for (final entry in apks.entries) {
          if (entry.key.contains(abi)) {
            _apkFileName = entry.key;
            return entry.value;
          }
        }
      }
      // Fallback: arm64 covers ~95% of devices, else first asset.
      for (final entry in apks.entries) {
        if (entry.key.contains('arm64-v8a')) {
          _apkFileName = entry.key;
          return entry.value;
        }
      }
      _apkFileName = apks.keys.first;
      return apks.values.first;
    } catch (_) {}
    return null;
  }

  /// Ordered device ABIs, most-preferred first.
  Future<List<String>> _deviceAbis() async {
    try {
      if (Platform.isAndroid) {
        final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
        if (abis.isNotEmpty) return abis;
      }
    } catch (_) {}
    return const ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  }

  /// Returns >0 if [a] > [b], 0 if equal, <0 if [a] < [b].
  /// Strips leading 'v', build metadata (+...), and prerelease (-...).
  int _compareVersions(String a, String b) {
    String clean(String v) =>
        v.trim().split('+').first.split('-').first.trim();
    List<int> parse(String v) => clean(v)
        .split('.')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }
}
