import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app_log_service.dart';

class MemoryService extends GetxService {
  late Box<String> _memoryBox;
  static const String boxName = 'user_memory';

  Future<MemoryService> init() async {
    _memoryBox = await Hive.openBox<String>(boxName);
    return this;
  }

  List<String> getAllMemories() {
    return _memoryBox.values.toList();
  }

  Future<void> addMemory(String fact) async {
    if (fact.trim().isEmpty) return;
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _memoryBox.put(key, fact);
    Get.find<AppLogService>().info('New memory stored: $fact', category: LogCategory.system);
  }

  Future<void> clearMemories() async {
    await _memoryBox.clear();
  }

  /// Injects memories into the system prompt.
  String injectMemories(String basePrompt) {
    final memories = getAllMemories();
    if (memories.isEmpty) return basePrompt;

    final buffer = StringBuffer(basePrompt);
    buffer.writeln('\n\n[User Context & Information]');
    for (final m in memories) {
      buffer.writeln('- $m');
    }
    return buffer.toString();
  }
}
