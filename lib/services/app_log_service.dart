import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'crash_reporting_service.dart';

enum LogCategory {
  system('System'),
  model('Model'),
  cloud('Cloud'),
  chat('Chat'),
  server('Server'),
  image('Image');

  final String label;
  const LogCategory(this.label);
}

class AppLogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? details;
  final LogCategory category;

  AppLogEntry({
    required this.level,
    required this.message,
    this.details,
    this.category = LogCategory.system,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isImportant => level == 'ERROR' || level == 'WARNING';

  Map<String, dynamic> toJson() => {
        't': timestamp.toIso8601String(),
        'l': level,
        'm': message,
        'd': details,
        'c': category.name,
      };

  factory AppLogEntry.fromJson(Map<String, dynamic> j) => AppLogEntry(
        timestamp: DateTime.parse(j['t']),
        level: j['l'],
        message: j['m'],
        details: j['d'],
        category: LogCategory.values.firstWhere(
          (e) => e.name == j['c'],
          orElse: () => LogCategory.system,
        ),
      );

  String format() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('$level [${category.label}]: $message');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n$details');
    }
    return buffer.toString();
  }
}

class CrashPattern {
  final String id;
  final String title;
  final String description;
  final String fix;
  final bool Function(AppLogEntry) matcher;
  int occurrences = 0;
  DateTime? lastSeen;

  CrashPattern({
    required this.id,
    required this.title,
    required this.description,
    required this.fix,
    required this.matcher,
  });
}

class AppLogService extends GetxService {
  final entries = <AppLogEntry>[].obs;
  final searchQuery = ''.obs;
  final selectedCategory = Rxn<LogCategory>();
  final selectedLevel = 'ALL'.obs;
  File? _logFile;
  static const int _maxEntries = 500;
  static const int _persistBatch = 25;

  final crashPatterns = <CrashPattern>[
    CrashPattern(
      id: 'model_file_missing',
      title: 'Model file missing',
      description: 'Saved model path no longer exists on device.',
      fix: 'Re-download the model from the Models tab.',
      matcher: (e) =>
          e.message.contains('Model file missing') ||
          e.message.contains('not on this device'),
    ),
    CrashPattern(
      id: 'context_overflow',
      title: 'Context window overflow',
      description: 'Input tokens exceed the context window size.',
      fix: 'Increase Context Window Size in Settings or start a new chat.',
      matcher: (e) =>
          e.message.contains('context') &&
          (e.message.contains('overflow') ||
              e.message.contains('exceed') ||
              e.message.contains('too long')),
    ),
    CrashPattern(
      id: 'model_load_failed',
      title: 'Model load failed',
      description: 'The inference engine could not load the model file.',
      fix: 'Check available RAM. Try a smaller quantization (Q4_K_M).',
      matcher: (e) =>
          e.message.contains('load') &&
          (e.message.contains('failed') || e.message.contains('error')) &&
          e.message.contains('model'),
    ),
    CrashPattern(
      id: 'gpu_error',
      title: 'GPU / Neural Engine error',
      description: 'Hardware acceleration failed, falling back to CPU.',
      fix: 'Disable GPU in Settings → Compute Backend, or try CPU.',
      matcher: (e) =>
          (e.message.contains('GPU') || e.message.contains('Neural Engine') ||
              e.message.contains('Vulkan') || e.message.contains('OpenCL')) &&
          (e.message.contains('fail') || e.message.contains('error')),
    ),
    CrashPattern(
      id: 'cloud_api_error',
      title: 'Cloud API error',
      description: 'Network request to cloud provider failed.',
      fix: 'Check internet connection and API key validity.',
      matcher: (e) =>
          e.category == LogCategory.cloud &&
          e.level == 'ERROR' &&
          (e.message.contains('request failed') ||
              e.message.contains('API') ||
              e.message.contains('401') ||
              e.message.contains('429')),
    ),
    CrashPattern(
      id: 'oom',
      title: 'Out of memory',
      description: 'Device ran out of memory during inference.',
      fix: 'Use a smaller model or reduce context window size.',
      matcher: (e) =>
          e.message.contains('OOM') ||
          e.message.contains('out of memory') ||
          e.message.contains('OutOfMemory') ||
          (e.message.contains('memory') && e.level == 'ERROR'),
    ),
    CrashPattern(
      id: 'generation_hang',
      title: 'Generation hang detected',
      description: 'Token stream stopped without completion signal.',
      fix: 'Tap Stop, then retry. If persistent, reload the model.',
      matcher: (e) =>
          e.message.contains('generation') &&
          (e.message.contains('hang') ||
              e.message.contains('timeout') ||
              e.message.contains('no tokens')),
    ),
    CrashPattern(
      id: 'slot_stale',
      title: 'Multi-model slot stale',
      description: 'A model slot pointed to an invalid native state.',
      fix: 'App self-healed. If recurring, restart the app.',
      matcher: (e) =>
          e.message.contains('slot') &&
          (e.message.contains('stale') || e.message.contains('invalid')),
    ),
    CrashPattern(
      id: 'import_failed',
      title: 'Model import failed',
      description: 'Could not copy the GGUF file to app storage.',
      fix: 'Ensure enough free storage and try again.',
      matcher: (e) =>
          e.message.contains('import') &&
          (e.message.contains('failed') || e.message.contains('error')),
    ),
    CrashPattern(
      id: 'firebase_init',
      title: 'Firebase initialization failed',
      description: 'Crash reporting could not start.',
      fix: 'Non-critical. App works without crash reporting.',
      matcher: (e) =>
          e.message.contains('Firebase') && e.message.contains('failed'),
    ),
  ];

  @override
  void onInit() {
    super.onInit();
    _loadPersistedLogs();
  }

  void warning(String message, {Object? details, LogCategory? category}) {
    _add('WARNING', message, details, category);
  }

  void error(String message, {Object? details, LogCategory? category}) {
    _add('ERROR', message, details, category);
  }

  void info(String message, {Object? details, LogCategory? category}) {
    _add('INFO', message, details, category);
  }

  void debug(String message, {Object? details, LogCategory? category}) {
    _add('DEBUG', message, details, category);
  }

  void _add(String level, String message, Object? details, LogCategory? cat) {
    final entry = AppLogEntry(
      level: level,
      message: message,
      details: details?.toString(),
      category: cat ?? LogCategory.system,
    );
    entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    if ((level == 'ERROR' || level == 'WARNING') &&
        Get.isRegistered<CrashReportingService>()) {
      Get.find<CrashReportingService>().recordNonFatal(
        details ?? message,
        reason: message,
        extra: {'app_log_level': level, 'category': (cat ?? LogCategory.system).name},
      );
    }
    if (entries.length % _persistBatch == 0) {
      _persistLogs();
    }
  }

  // --- Search & Filter ---

  List<AppLogEntry> get filteredEntries {
    var result = entries.toList();

    if (selectedLevel.value != 'ALL') {
      result = result.where((e) => e.level == selectedLevel.value).toList();
    }
    if (selectedCategory.value != null) {
      result =
          result.where((e) => e.category == selectedCategory.value).toList();
    }
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isNotEmpty) {
      result = result
          .where((e) =>
              e.message.toLowerCase().contains(q) ||
              (e.details?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return result;
  }

  List<AppLogEntry> get importantEntries =>
      entries.where((entry) => entry.isImportant).toList();

  // --- Health Diagnostics ---

  int get errorCount => entries.where((e) => e.level == 'ERROR').length;
  int get warningCount => entries.where((e) => e.level == 'WARNING').length;

  DateTime? get lastError {
    try {
      return entries.firstWhere((e) => e.level == 'ERROR').timestamp;
    } catch (_) {}
    return null;
  }

  List<CrashPattern> get detectedPatterns {
    final detected = <CrashPattern>[];
    for (final pattern in crashPatterns) {
      final matches = entries.where((e) => pattern.matcher(e)).toList();
      if (matches.isNotEmpty) {
        pattern.occurrences = matches.length;
        pattern.lastSeen = matches.first.timestamp;
        detected.add(pattern);
      }
    }
    detected.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return detected;
  }

  Map<String, int> get categoryBreakdown {
    final map = <String, int>{};
    for (final cat in LogCategory.values) {
      final count = entries.where((e) => e.category == cat).length;
      if (count > 0) map[cat.label] = count;
    }
    return map;
  }

  String get healthSummary {
    final patterns = detectedPatterns;
    final buf = StringBuffer();
    buf.writeln('=== CubicLM System Health ===');
    buf.writeln('Total logs: ${entries.length}');
    buf.writeln('Errors: $errorCount  |  Warnings: $warningCount');
    if (lastError != null) {
      buf.writeln('Last error: ${_fmtTime(lastError!)}');
    }
    buf.writeln('');
    if (patterns.isEmpty) {
      buf.writeln('✓ No crash patterns detected.');
    } else {
      buf.writeln('Crash patterns detected (${patterns.length}):');
      for (final p in patterns) {
        buf.writeln('  • ${p.title} (${p.occurrences}x)');
        buf.writeln('    Fix: ${p.fix}');
      }
    }
    buf.writeln('');
    buf.writeln('Category breakdown:');
    for (final entry in categoryBreakdown.entries) {
      buf.writeln('  ${entry.key}: ${entry.value}');
    }
    return buf.toString();
  }

  // --- Persistence ---

  Future<File> get _file async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/cubiclm_logs.json');
    return _logFile!;
  }

  Future<void> _persistLogs() async {
    try {
      final f = await _file;
      final json = entries.take(200).map((e) => e.toJson()).toList();
      await f.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  Future<void> _loadPersistedLogs() async {
    try {
      final f = await _file;
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        final loaded = json.map((j) => AppLogEntry.fromJson(j)).toList();
        entries.assignAll(loaded);
      }
    } catch (_) {}
  }

  // --- Export ---

  Future<void> copyImportantLogs() async {
    await Clipboard.setData(ClipboardData(text: shareText));
  }

  Future<String> exportFullLogs() async {
    final buf = StringBuffer();
    buf.writeln(healthSummary);
    buf.writeln('');
    buf.writeln('=== Full Log ===');
    for (final e in entries) {
      buf.writeln(e.format());
      buf.writeln('');
    }
    return buf.toString();
  }

  String get shareText {
    final selected = importantEntries.isEmpty ? entries : importantEntries;
    return selected.map((entry) => entry.format()).join('\n\n');
  }

  void clear() {
    entries.clear();
    _persistLogs();
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
