import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Detected SoC family.
enum SocFamily {
  apple,
  snapdragon,
  mediatek,
  exynos,
  googleTensor,
  unisoc,
  rockchip,
  hisilicon,
  unknown,
}

extension SocFamilyExt on SocFamily {
  String get displayName {
    switch (this) {
      case SocFamily.apple:
        return 'Apple Silicon';
      case SocFamily.snapdragon:
        return 'Qualcomm Snapdragon';
      case SocFamily.mediatek:
        return 'MediaTek Dimensity';
      case SocFamily.exynos:
        return 'Samsung Exynos';
      case SocFamily.googleTensor:
        return 'Google Tensor';
      case SocFamily.unisoc:
        return 'Unisoc';
      case SocFamily.rockchip:
        return 'Rockchip';
      case SocFamily.hisilicon:
        return 'Huawei Kirin';
      case SocFamily.unknown:
        return 'Unknown';
    }
  }

  String get recommendedQuant {
    switch (this) {
      case SocFamily.apple:
        return 'Q4_K_M (safe default) · Q5_K_M for quality';
      case SocFamily.snapdragon:
        return 'Q4_K_M (recommended) · Q4_0_4_8 on X Elite';
      case SocFamily.mediatek:
        return 'Q4_K_M (recommended)';
      case SocFamily.exynos:
        return 'Q4_K_M (recommended)';
      case SocFamily.googleTensor:
        return 'Q4_0 or Q5_K_M · AVOID Q4_K_M';
      case SocFamily.unisoc:
        return 'Q4_K_M (recommended)';
      case SocFamily.rockchip:
        return 'Q4_K_M (recommended)';
      case SocFamily.hisilicon:
        return 'Q4_K_M (recommended)';
      case SocFamily.unknown:
        return 'Q4_K_M (universal default)';
    }
  }

  String? get quantWarning {
    switch (this) {
      case SocFamily.googleTensor:
        return 'Google Tensor has a known bug with Q4_K_M quantization that produces empty or garbled responses. Use Q4_0 or Q5_K_M models instead.';
      default:
        return null;
    }
  }
}

SocFamily _detectSocFamily(String cpuinfo, String hardware) {
  final lower = cpuinfo.toLowerCase();
  final hwLower = hardware.toLowerCase();

  // Google Tensor (Pixel 6/7/8/9)
  if (RegExp(r'gs\d{3}').hasMatch(hwLower) ||
      lower.contains('google tensor')) {
    return SocFamily.googleTensor;
  }

  // Qualcomm Snapdragon
  if (hwLower.contains('qcom') ||
      hwLower.contains('qualcomm') ||
      hwLower.contains('snapdragon') ||
      RegExp(r'\bsm\d{4,}').hasMatch(hwLower) ||
      lower.contains('snapdragon')) {
    return SocFamily.snapdragon;
  }

  // MediaTek Dimensity / Helio
  if (hwLower.contains('mt6') ||
      hwLower.contains('mt8') ||
      lower.contains('mediatek') ||
      lower.contains('dimensity') ||
      lower.contains('helio')) {
    return SocFamily.mediatek;
  }

  // Samsung Exynos
  if (hwLower.contains('exynos') || lower.contains('exynos')) {
    return SocFamily.exynos;
  }

  // Unisoc
  if (hwLower.contains('unisoc') ||
      hwLower.contains('spreadtrum') ||
      RegExp(r'\bsc\d{4}').hasMatch(hwLower)) {
    return SocFamily.unisoc;
  }

  // Rockchip
  if (hwLower.contains('rockchip') || RegExp(r'\brk\d').hasMatch(hwLower)) {
    return SocFamily.rockchip;
  }

  // Huawei Hisilicon / Kirin
  if (hwLower.contains('hisilicon') ||
      lower.contains('kirin') ||
      lower.contains('hisi')) {
    return SocFamily.hisilicon;
  }

  // Apple (iOS path doesn't hit this, but keep for completeness)
  if (lower.contains('apple')) {
    return SocFamily.apple;
  }

  return SocFamily.unknown;
}

/// Native (Android/iOS/macOS/Linux) device info implementation.
Future<Map<String, dynamic>> getDeviceInfo() async {
  double totalRam = 4.0;
  double availableRam = 2.0;
  SocFamily socFamily = SocFamily.unknown;
  String hardware = '';
  String processor = '';
  String gpuName = '';

  try {
    if (Platform.isAndroid || Platform.isLinux) {
      final meminfo = await File('/proc/meminfo').readAsString();
      final totalMatch = RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo);
      if (totalMatch != null) {
        totalRam = int.parse(totalMatch.group(1)!) / 1024 / 1024;
      }
      final availMatch = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(meminfo);
      if (availMatch != null) {
        availableRam = int.parse(availMatch.group(1)!) / 1024 / 1024;
      }

      // Detect SoC family from /proc/cpuinfo
      try {
        final cpuinfo = await File('/proc/cpuinfo').readAsString();
        hardware = RegExp(r'Hardware\s*:\s*(.+)', caseSensitive: false)
                .firstMatch(cpuinfo)
                ?.group(1)
                ?.trim() ??
            '';
        socFamily = _detectSocFamily(cpuinfo, hardware);
      } catch (_) {}

      // Modern Android hides the cpuinfo "Hardware" line — read system
      // properties instead (Android 12+ exposes ro.soc.*).
      if (Platform.isAndroid) {
        Future<String> getProp(String name) async {
          try {
            final r = await Process.run('getprop', [name]);
            return r.stdout.toString().trim();
          } catch (_) {
            return '';
          }
        }

        final socManufacturer = await getProp('ro.soc.manufacturer');
        final socModel = await getProp('ro.soc.model');
        final boardPlatform = await getProp('ro.board.platform');
        final roHardware = await getProp('ro.hardware');
        final brand = await getProp('ro.product.brand');
        final model = await getProp('ro.product.model');

        // Improve family detection using the properties we now have.
        final combined =
            '$socManufacturer $socModel $boardPlatform $roHardware $hardware';
        if (socFamily == SocFamily.unknown && combined.trim().isNotEmpty) {
          socFamily = _detectSocFamily(combined.toLowerCase(), combined);
        }

        processor = _buildProcessorName(
          manufacturer: socManufacturer,
          socModel: socModel,
          boardPlatform: boardPlatform,
          hardware: hardware.isNotEmpty ? hardware : roHardware,
          brand: brand,
          model: model,
        );

        // GPU renderer name from the llama plugin's Vulkan probe.
        try {
          final gpu = await LlamaHostApi().detectGpu();
          gpuName = gpu.gpuName == 'None' ? '' : gpu.gpuName;
        } catch (_) {}
      }
    } else if (Platform.isIOS) {
      final plugin = LlamaHostApi();
      final gpuInfo = await plugin.detectGpu();
      totalRam = gpuInfo.deviceLocalMemoryBytes / (1024 * 1024 * 1024);
      availableRam = gpuInfo.freeRamBytes / (1024 * 1024 * 1024);
      socFamily = SocFamily.apple;
      gpuName = gpuInfo.gpuName;
    } else if (Platform.isMacOS) {
      totalRam = 16.0;
      availableRam = 8.0;
      socFamily = SocFamily.apple;
    } else if (Platform.isWindows) {
      // Real RAM via device_info_plus (Credential-Locker-grade plugin,
      // already a dependency). Before this, Windows fell through to the
      // 4 GB / 2 GB fiction above and mistuned context/maxTokens.
      try {
        final win = await DeviceInfoPlugin().windowsInfo;
        final memMb = win.systemMemoryInMegabytes;
        if (memMb > 0) {
          totalRam = memMb / 1024;
          // The plugin exposes no free-RAM counter — assume half usable.
          availableRam = totalRam / 2;
        }
        processor = 'Windows PC · ${win.numberOfCores} cores';
        hardware = 'x86_64';
      } catch (_) {}
    }
  } catch (e) {
    print('[DeviceInfo] Failed to read device info: $e');
  }

  return {
    'totalRamGB': totalRam,
    'availableRamGB': availableRam,
    'isTensorSoC': socFamily == SocFamily.googleTensor ? 1.0 : 0.0,
    'socFamily': socFamily.index,
    'socHardware': hardware,
    'processor': processor,
    'gpuName': gpuName,
  };
}

/// Builds a human-readable processor name from Android system properties.
///
/// Prefers the marketing name for known Qualcomm/Google parts; falls back
/// to "<Manufacturer> <Model>" then the raw board/hardware string.
String _buildProcessorName({
  required String manufacturer,
  required String socModel,
  required String boardPlatform,
  required String hardware,
  required String brand,
  required String model,
}) {
  final m = socModel.toUpperCase().trim();

  const qualcommNames = <String, String>{
    'SM8750': 'Snapdragon 8 Elite',
    'SM8650': 'Snapdragon 8 Gen 3',
    'SM8550-AC': 'Snapdragon 8 Gen 2',
    'SM8550': 'Snapdragon 8 Gen 2',
    'SM8475': 'Snapdragon 8+ Gen 1',
    'SM8450': 'Snapdragon 8 Gen 1',
    'SM8350': 'Snapdragon 888',
    'SM8250': 'Snapdragon 865',
    'SM7325': 'Snapdragon 778G',
    'SM7450-AB': 'Snapdragon 7 Gen 1',
    'SM6375': 'Snapdragon 695',
    'SDM678': 'Snapdragon 675',
    'QCM6490': 'Snapdragon 778G',
  };

  const googleNames = <String, String>{
    'GS101': 'Google Tensor',
    'GS201': 'Google Tensor G2',
    'ZUMA': 'Google Tensor G3',
    'ZUMAPRO': 'Google Tensor G4',
  };

  String? name;
  if (m.startsWith('SM') || m.startsWith('SDM') || m.startsWith('QCM')) {
    name = qualcommNames[m] ?? _fuzzyQualcomm(m);
  } else if (googleNames.containsKey(m)) {
    name = googleNames[m];
  } else if (m.startsWith('MT')) {
    final dimensity = _mediatekMarketing(socModel.toUpperCase());
    name = dimensity ?? 'MediaTek ${socModel.toUpperCase()}';
  } else if (m.contains('EXYNOS') ||
      boardPlatform.toUpperCase().contains('EXYNOS') ||
      hardware.toUpperCase().contains('EXYNOS')) {
    name = 'Samsung Exynos ${_extractDigits(socModel)}'.trim();
  } else if (m.contains('TENSOR')) {
    name = googleNames['GS101'];
  }

  name ??= [
    if (manufacturer.trim().isNotEmpty) _prettyVendor(manufacturer),
    if (socModel.trim().isNotEmpty)
      socModel.trim().toUpperCase() == socModel.trim()
          ? socModel.trim()
          : socModel.trim(),
  ].where((s) => s.isNotEmpty).join(' ');

  if (name.isEmpty) {
    name = hardware.trim();
  }

  // Append device identity when it adds information (e.g. emulator).
  if (name.isEmpty && brand.isNotEmpty) {
    name = '$brand $model'.trim();
  }
  return name.trim();
}

String? _fuzzyQualcomm(String model) {
  // SM8xxx → Snapdragon 8 series; SM7xxx → 7 series etc.
  final match = RegExp(r'^SM([678])(\d{3})').firstMatch(model);
  if (match == null) return null;
  final series = match.group(1);
  return 'Snapdragon $series series (${model.toLowerCase()})';
}

String? _mediatekMarketing(String model) {
  final map = <String, String>{
    'MT6985': 'Dimensity 9200',
    'MT6983': 'Dimensity 9000',
    'MT6896': 'Dimensity 8200',
    'MT6895': 'Dimensity 8100',
    'MT6893': 'Dimensity 1200',
    'MT6877': 'Dimensity 900',
    'MT6833': 'Dimensity 700',
  };
  return map[model];
}

String _extractDigits(String s) =>
    RegExp(r'\d+[A-Za-z]*').firstMatch(s)?.group(0) ?? '';

String _prettyVendor(String raw) {
  switch (raw.toLowerCase()) {
    case 'qcom':
    case 'qualcomm':
      return 'Qualcomm';
    case 'mediatek':
      return 'MediaTek';
    case 'google':
      return 'Google';
    case 'samsung':
      return 'Samsung';
    case 'hisilicon':
      return 'HiSilicon';
    case 'unisoc':
      return 'Unisoc';
    default:
      return raw[0].toUpperCase() + raw.substring(1).toUpperCase();
  }
}
